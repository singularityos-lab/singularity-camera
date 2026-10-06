namespace Singularity.Apps.Camera {

    public class CameraDevice : Object {
        public string name;
        public Gst.Device? device;
        public string? description;

        public CameraDevice (Gst.Device device) {
            this.device = device;
            this.name = device.display_name;
        }

        public CameraDevice.from_description (string description) {
            this.description = description;
            this.name = description;
        }

        public Gst.Element? create_source () throws Error {
            if (device != null) return device.create_element ("source");
            return Gst.parse_bin_from_description (description, true);
        }
    }

    public class CameraEngine : Object {
        private Gst.DeviceMonitor monitor;
        private Gst.DeviceMonitor mic_monitor;
        private bool record_audio;
        private Gst.Pipeline? pipeline;
        private Gst.App.Sink? sink;
        private Gst.Element? audio_src;
        private uint bus_watch;
        private Gst.Sample? last;
        private string? recording_path;
        private int64 record_start;
        public Gee.ArrayList<CameraDevice> devices = new Gee.ArrayList<CameraDevice> ();
        public int current = 0;
        public bool recording { get; private set; }
        public int width { get; private set; }
        public int height { get; private set; }
        public string error_message { get; private set; default = ""; }

        public signal void frame (Gdk.Texture texture);
        public signal void devices_changed ();
        public signal void recording_saved (string path);
        public signal void failed (string message);

        public CameraEngine () {
            monitor = new Gst.DeviceMonitor ();
            var caps = new Gst.Caps.empty_simple ("video/x-raw");
            monitor.add_filter ("Video/Source", caps);
            var bus = monitor.get_bus ();
            bus.add_watch (Priority.DEFAULT, (b, msg) => {
                if (msg.type == Gst.MessageType.DEVICE_ADDED || msg.type == Gst.MessageType.DEVICE_REMOVED) {
                    refresh ();
                    devices_changed ();
                }
                return true;
            });
            monitor.start ();
            mic_monitor = new Gst.DeviceMonitor ();
            mic_monitor.add_filter ("Audio/Source", null);
            refresh ();
        }

        private void refresh () {
            devices.clear ();
            var seen = new Gee.HashSet<string> ();
            string? test_source = Environment.get_variable ("SINGULARITY_CAMERA_SOURCE");
            if (test_source != null && test_source != "") devices.add (new CameraDevice.from_description (test_source));
            foreach (var d in monitor.get_devices ()) {
                if (!seen.add (d.display_name)) continue;
                devices.add (new CameraDevice (d));
            }
            if (current >= devices.size) current = 0;
        }

        public bool has_camera () {
            return devices.size > 0;
        }

        private Gst.Element make (string factory, string? name = null) throws Error {
            var e = Gst.ElementFactory.make (factory, name);
            if (e == null) throw new IOError.NOT_FOUND (_("The %s component of GStreamer is missing.").printf (factory));
            return e;
        }

        public void start () {
            stop ();
            error_message = "";
            if (devices.size == 0) return;
            try {
                build (false);
                pipeline.set_state (Gst.State.PLAYING);
            } catch (Error e) {
                error_message = e.message;
                failed (e.message);
                stop ();
            }
        }

        private void build (bool record) throws Error {
            pipeline = new Gst.Pipeline ("camera");
            var src = devices[current].create_source ();
            if (src == null) throw new IOError.FAILED (_("The camera could not be opened."));
            var convert = make ("videoconvert");
            var tee = make ("tee");
            var q1 = make ("queue");
            var scale = make ("videoconvert", "preview-convert");
            var appsink = (Gst.App.Sink) make ("appsink");
            appsink.caps = Gst.Caps.from_string ("video/x-raw,format=RGBA");
            appsink.max_buffers = 1;
            appsink.drop = true;
            appsink.emit_signals = true;
            appsink.sync = false;
            appsink.new_sample.connect (on_sample);
            sink = appsink;
            q1.set ("leaky", 2);
            pipeline.add_many (src, convert, tee, q1, scale, appsink);
            if (!src.link (convert) || !convert.link (tee) || !tee.link (q1) || !q1.link (scale) || !scale.link (appsink)) throw new IOError.FAILED (_("The camera stream could not be set up."));
            if (record) {
                var q2 = make ("queue");
                var vconv = make ("videoconvert", "record-convert");
                var enc = make ("vp8enc");
                enc.set ("deadline", (int64) 1);
                enc.set ("cpu-used", 8);
                enc.set ("target-bitrate", 4000000);
                enc.set ("threads", 4);
                var mux = make ("webmmux");
                var fsink = make ("filesink");
                fsink.set ("location", recording_path);
                pipeline.add_many (q2, vconv, enc, mux, fsink);
                if (!tee.link (q2) || !q2.link (vconv) || !vconv.link (enc) || !enc.link (mux) || !mux.link (fsink)) throw new IOError.FAILED (_("Video recording could not be set up."));
                if (record_audio) try {
                    audio_src = make ("autoaudiosrc");
                    var aconv = make ("audioconvert");
                    var ares = make ("audioresample");
                    var aenc = make ("opusenc");
                    var aq = make ("queue");
                    pipeline.add_many (audio_src, aq, aconv, ares, aenc);
                    if (!audio_src.link (aq) || !aq.link (aconv) || !aconv.link (ares) || !ares.link (aenc) || !aenc.link (mux)) {
                        audio_src = null;
                    }
                } catch (Error e) {
                    audio_src = null;
                }
            }
            var bus = pipeline.get_bus ();
            bus_watch = bus.add_watch (Priority.DEFAULT, on_bus);
        }

        private bool on_bus (Gst.Bus bus, Gst.Message msg) {
            switch (msg.type) {
                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    msg.parse_error (out err, out debug);
                    if (recording && record_audio && audio_src != null && msg.src != null && msg.src.has_as_ancestor (audio_src)) {
                        record_audio = false;
                        string path = recording_path;
                        stop ();
                        recording_path = path;
                        try {
                            build (true);
                            pipeline.set_state (Gst.State.PLAYING);
                        } catch (Error e) {
                            recording = false;
                            recording_path = null;
                            failed (e.message);
                            start ();
                        }
                        break;
                    }
                    error_message = err.message;
                    failed (err.message);
                    break;
                case Gst.MessageType.EOS:
                    if (recording_path != null) {
                        string done = recording_path;
                        recording_path = null;
                        recording = false;
                        pipeline.set_state (Gst.State.NULL);
                        recording_saved (done);
                        Idle.add (() => {
                            start ();
                            return Source.REMOVE;
                        });
                    }
                    break;
                default:
                    break;
            }
            return true;
        }

        private Gst.FlowReturn on_sample (Gst.App.Sink s) {
            var sample = s.pull_sample ();
            if (sample == null) return Gst.FlowReturn.OK;
            last = sample;
            Idle.add (() => {
                present (sample);
                return Source.REMOVE;
            });
            return Gst.FlowReturn.OK;
        }

        private void present (Gst.Sample sample) {
            var tex = to_texture (sample);
            if (tex != null) frame (tex);
        }

        public Gdk.Texture? to_texture (Gst.Sample sample) {
            var caps = sample.get_caps ();
            unowned Gst.Structure st = caps.get_structure (0);
            int w, h;
            st.get_int ("width", out w);
            st.get_int ("height", out h);
            width = w;
            height = h;
            var buffer = sample.get_buffer ();
            Gst.MapInfo map;
            if (!buffer.map (out map, Gst.MapFlags.READ)) return null;
            var video = new Gst.Video.Info ();
            int stride = w * 4;
            if (video.from_caps (caps)) stride = video.stride[0];
            var bytes = new Bytes (map.data);
            buffer.unmap (map);
            return new Gdk.MemoryTexture (w, h, Gdk.MemoryFormat.R8G8B8A8, bytes, stride);
        }

        public void stop () {
            if (pipeline != null) {
                pipeline.set_state (Gst.State.NULL);
                if (bus_watch != 0) Source.remove (bus_watch);
                bus_watch = 0;
                pipeline = null;
            }
            sink = null;
            audio_src = null;
        }

        public static string next_path (string dir_kind, string prefix, string ext) {
            string base_dir = Environment.get_user_special_dir (dir_kind == "video" ? UserDirectory.VIDEOS : UserDirectory.PICTURES) ?? Environment.get_home_dir ();
            string dir = Path.build_filename (base_dir, "Camera");
            DirUtils.create_with_parents (dir, 0755);
            string stamp = new DateTime.now_local ().format ("%Y%m%d_%H%M%S");
            string path = Path.build_filename (dir, "%s_%s.%s".printf (prefix, stamp, ext));
            int n = 1;
            while (FileUtils.test (path, FileTest.EXISTS)) path = Path.build_filename (dir, "%s_%s_%d.%s".printf (prefix, stamp, n++, ext));
            return path;
        }

        public string? take_photo (bool mirror) throws Error {
            if (last == null) throw new IOError.FAILED (_("There is no picture from the camera yet."));
            var tex = to_texture (last);
            if (tex == null) throw new IOError.FAILED (_("The picture could not be read."));
            var downloader = new Gdk.TextureDownloader (tex);
            downloader.set_format (Gdk.MemoryFormat.R8G8B8);
            size_t stride;
            var bytes = downloader.download_bytes (out stride);
            var pix = new Gdk.Pixbuf.from_bytes (bytes, Gdk.Colorspace.RGB, false, 8, tex.width, tex.height, (int) stride);
            if (mirror) pix = pix.flip (true);
            string path = next_path ("photo", "IMG", "jpg");
            try {
                pix.savev (path, "jpeg", { "quality" }, { "92" });
            } catch (Error e) {
                warning ("camera: %s", e.message);
                FileUtils.remove (path);
                throw new IOError.FAILED (_("The photo could not be saved."));
            }
            return path;
        }

        public void start_recording () throws Error {
            if (recording || devices.size == 0) return;
            recording_path = next_path ("video", "VID", "webm");
            record_audio = mic_monitor.get_devices ().length () > 0;
            stop ();
            try {
                build (true);
            } catch (Error e) {
                recording_path = null;
                start ();
                throw e;
            }
            pipeline.set_state (Gst.State.PLAYING);
            recording = true;
            record_start = get_monotonic_time ();
        }

        public void stop_recording () {
            if (!recording || pipeline == null) return;
            pipeline.send_event (new Gst.Event.eos ());
        }

        public double recording_seconds () {
            return recording ? (get_monotonic_time () - record_start) / 1000000.0 : 0;
        }

        public void next_camera () {
            if (devices.size < 2 || recording) return;
            current = (current + 1) % devices.size;
            start ();
        }
    }
}
