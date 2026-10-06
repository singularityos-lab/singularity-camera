using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Camera {

    public class LastShot : Widget {
        private const int SIZE = 52;
        private Gdk.Paintable? _paintable;

        public Gdk.Paintable? paintable {
            get { return _paintable; }
            set {
                _paintable = value;
                queue_draw ();
            }
        }

        protected override void measure (Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum = natural = SIZE;
            minimum_baseline = natural_baseline = -1;
        }

        protected override void snapshot (Gtk.Snapshot snapshot) {
            if (_paintable == null) return;
            float w = get_width (), h = get_height ();
            double iw = _paintable.get_intrinsic_width (), ih = _paintable.get_intrinsic_height ();
            if (iw <= 0 || ih <= 0) return;
            double scale = double.max (w / iw, h / ih);
            double dw = iw * scale, dh = ih * scale;
            var rect = Graphene.Rect ().init (0, 0, w, h);
            var rounded = Gsk.RoundedRect ().init_from_rect (rect, 12);
            snapshot.push_rounded_clip (rounded);
            snapshot.save ();
            snapshot.translate (Graphene.Point ().init ((float) ((w - dw) / 2), (float) ((h - dh) / 2)));
            _paintable.snapshot (snapshot, dw, dh);
            snapshot.restore ();
            snapshot.pop ();
        }
    }

    public class CameraWindow : Singularity.Widgets.Window {
        private CameraEngine engine;
        private Stack stack;
        private Picture preview;
        private Overlay overlay;
        private Button shutter;
        private Label shutter_time;
        private ToggleButton photo_mode;
        private ToggleButton video_mode;
        private Button switch_button;
        private Button last_button;
        private LastShot last_picture;
        private Label countdown;
        private Box flash;
        private Button timer_bubble;
        private uint aspect_id;
        private int aspect_w;
        private int aspect_h;
        private Button mirror_bubble;
        private int timer_seconds;
        private bool mirror = true;
        private string? last_path;
        private uint tick_id;
        private bool counting;

        public CameraWindow (Gtk.Application app) {
            Object (application: app);
            set_default_size (960, 720);
            set_title (_("Camera"));
            engine = new CameraEngine ();

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.add_named (build_welcome (), "none");
            stack.add_named (build_camera (), "camera");
            set_content (stack);

            timer_bubble = add_bubble_icon ("camera-timer-symbolic", _("Timer: Off"), () => cycle_timer ());
            mirror_bubble = add_bubble_icon ("camera-mirror-symbolic", _("Mirror Preview"), () => {
                lookup_action ("mirror").activate (null);
            });
            add_bubble_icon ("folder-pictures-symbolic", _("Open Camera Folder"), () => open_folder ());
            install_actions ();

            engine.frame.connect ((tex) => {
                preview.paintable = tex;
                if (tex.width != aspect_w || tex.height != aspect_h) {
                    aspect_w = tex.width;
                    aspect_h = tex.height;
                    schedule_aspect ();
                }
            });
            notify["default-width"].connect (schedule_aspect);
            notify["default-height"].connect (schedule_aspect);
            engine.devices_changed.connect (() => {
                sync_devices ();
                if (engine.has_camera () && stack.visible_child_name != "camera") {
                    stack.visible_child_name = "camera";
                    engine.start ();
                } else if (!engine.has_camera () && stack.visible_child_name == "camera") {
                    if (engine.recording) engine.stop_recording ();
                    engine.stop ();
                    preview.paintable = null;
                    stack.visible_child_name = "none";
                }
            });
            stack.notify["visible-child-name"].connect (() => {
                bool live = stack.visible_child_name == "camera";
                timer_bubble.visible = live;
                mirror_bubble.visible = live;
                sync_live_actions ();
            });
            engine.failed.connect ((m) => show_toast (m));
            engine.recording_saved.connect ((path) => {
                last_path = path;
                update_last ();
                sync_shutter ();
            });
            engine.notify["recording"].connect (sync_shutter);
            close_request.connect (() => {
                if (engine.recording) engine.stop_recording ();
                engine.stop ();
                return false;
            });
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, st) => {
                if (keyval == Gdk.Key.space || keyval == Gdk.Key.Return) {
                    shoot ();
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);
            sync_devices ();
            sync_mirror ();
            find_last ();
            sync_live_actions ();
            if (engine.has_camera ()) {
                stack.visible_child_name = "camera";
                engine.start ();
            } else {
                stack.visible_child_name = "none";
                timer_bubble.visible = false;
                mirror_bubble.visible = false;
            }
        }

        private void install_actions () {
            var entries = new ActionEntry[] {
                { "shoot", () => shoot () },
                { "mode", null, "s", "'photo'", on_mode_change },
                { "timer", null, "i", "0", on_timer_change },
                { "mirror", null, null, "true", on_mirror_change },
                { "switch-camera", () => engine.next_camera () },
                { "rescan", () => engine.devices_changed () },
                { "open-last", () => {
                    if (last_path != null) new FileLauncher (File.new_for_path (last_path)).launch.begin (this, null);
                } },
                { "open-folder", () => open_folder () },
                { "fullscreen", () => {
                    if (fullscreened) unfullscreen ();
                    else fullscreen ();
                } },
                { "close", () => close () }
            };
            add_action_entries (entries, this);
        }

        private void set_action_enabled (string name, bool enabled) {
            var action = lookup_action (name) as SimpleAction;
            if (action != null) action.set_enabled (enabled);
        }

        private void sync_live_actions () {
            bool live = stack.visible_child_name == "camera";
            set_action_enabled ("shoot", live);
            set_action_enabled ("timer", live);
            set_action_enabled ("mirror", live);
            set_action_enabled ("mode", live && !engine.recording);
            set_action_enabled ("switch-camera", live && engine.devices.size > 1);
        }

        public void select_mode (string mode) {
            if (engine.recording) return;
            if (mode == "video") video_mode.active = true;
            else photo_mode.active = true;
        }

        private void on_mode_change (SimpleAction action, Variant? value) {
            if (engine.recording) return;
            if (value.get_string () == "video") video_mode.active = true;
            else photo_mode.active = true;
        }

        private void on_timer_change (SimpleAction action, Variant? value) {
            int seconds = value.get_int32 ();
            if (seconds != 0 && seconds != 3 && seconds != 10) return;
            apply_timer (seconds);
        }

        private void on_mirror_change (SimpleAction action, Variant? value) {
            mirror = value.get_boolean ();
            sync_mirror ();
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.camera";
            wp.title = _("Camera");
            wp.subtitle = _("No camera found. Connect a camera, or check that it is turned on and not used by another app.");
            wp.add_action ("camera-web", _("Look Again"), _("Search for cameras once more"), () => {
                engine.devices_changed ();
            });
            wp.add_action ("folder-pictures", _("Photos and Videos"), _("Open the folder with your shots"), () => open_folder ());
            return wp;
        }

        private Widget build_camera () {
            overlay = new Overlay ();
            overlay.add_css_class ("camera-stage");
            preview = new Picture ();
            preview.content_fit = ContentFit.CONTAIN;
            preview.hexpand = true;
            preview.vexpand = true;
            preview.add_css_class ("camera-preview");
            overlay.child = preview;

            flash = new Box (Orientation.VERTICAL, 0);
            flash.add_css_class ("camera-flash");
            flash.can_target = false;
            flash.opacity = 0;
            overlay.add_overlay (flash);

            countdown = new Label ("");
            countdown.add_css_class ("camera-countdown");
            countdown.visible = false;
            countdown.can_target = false;
            overlay.add_overlay (countdown);

            var bar = new CenterBox ();
            bar.add_css_class ("camera-bar");
            bar.valign = Align.END;
            bar.margin_bottom = 18;
            bar.margin_start = 24;
            bar.margin_end = 24;

            last_button = new Button ();
            last_button.add_css_class ("camera-last");
            last_button.tooltip_text = _("Open Last Shot");
            last_picture = new LastShot ();
            last_button.child = last_picture;
            last_button.valign = Align.CENTER;
            last_button.clicked.connect (() => {
                if (last_path != null) new FileLauncher (File.new_for_path (last_path)).launch.begin (this, null);
            });
            bar.start_widget = last_button;

            var center = new Box (Orientation.VERTICAL, 10);
            center.halign = Align.CENTER;
            shutter = new Button ();
            shutter.add_css_class ("camera-shutter");
            shutter.tooltip_text = _("Take a Photo (Space)");
            var inner = new Box (Orientation.VERTICAL, 0);
            inner.add_css_class ("camera-shutter-inner");
            inner.halign = Align.CENTER;
            inner.valign = Align.CENTER;
            shutter.child = inner;
            shutter.halign = Align.CENTER;
            shutter.clicked.connect (shoot);
            center.append (shutter);
            shutter_time = new Label ("");
            shutter_time.add_css_class ("camera-time");
            shutter_time.visible = false;
            center.append (shutter_time);
            var modes = new Box (Orientation.HORIZONTAL, 4);
            modes.add_css_class ("camera-modes");
            modes.halign = Align.CENTER;
            photo_mode = new ToggleButton.with_label (_("Photo"));
            video_mode = new ToggleButton.with_label (_("Video"));
            video_mode.group = photo_mode;
            photo_mode.active = true;
            photo_mode.add_css_class ("camera-mode");
            video_mode.add_css_class ("camera-mode");
            photo_mode.toggled.connect (sync_shutter);
            photo_mode.toggled.connect (() => {
                var mode_action = lookup_action ("mode") as SimpleAction;
                if (mode_action != null) mode_action.set_state (new Variant.string (photo_mode.active ? "photo" : "video"));
            });
            modes.append (photo_mode);
            modes.append (video_mode);
            center.append (modes);
            bar.center_widget = center;

            switch_button = new Button.from_icon_name ("camera-switch-symbolic");
            switch_button.add_css_class ("camera-round");
            switch_button.tooltip_text = _("Switch Camera");
            switch_button.valign = Align.CENTER;
            switch_button.clicked.connect (() => engine.next_camera ());
            bar.end_widget = switch_button;
            overlay.add_overlay (bar);
            return overlay;
        }

        private void schedule_aspect () {
            if (aspect_id != 0) Source.remove (aspect_id);
            aspect_id = Timeout.add (200, () => {
                aspect_id = 0;
                keep_aspect ();
                return Source.REMOVE;
            });
        }

        private void keep_aspect () {
            if (maximized || fullscreened || aspect_w <= 0 || aspect_h <= 0) return;
            if (stack.visible_child_name != "camera") return;
            int pw = preview.get_width ();
            int ph = preview.get_height ();
            if (pw <= 0 || ph <= 0) return;
            int want = (int) Math.round ((double) pw * aspect_h / aspect_w);
            if ((want - ph).abs () <= 2) return;
            set_default_size (default_width, default_height + want - ph);
        }

        private void sync_devices () {
            if (switch_button != null) switch_button.visible = engine.devices.size > 1;
            set_action_enabled ("switch-camera", stack != null && stack.visible_child_name == "camera" && engine.devices.size > 1);
        }

        private void sync_mirror () {
            if (mirror) preview.add_css_class ("mirrored");
            else preview.remove_css_class ("mirrored");
            mirror_bubble.tooltip_text = mirror ? _("Preview Is Mirrored") : _("Preview Is Not Mirrored");
            var mirror_action = lookup_action ("mirror") as SimpleAction;
            if (mirror_action != null) mirror_action.set_state (new Variant.boolean (mirror));
        }

        private void cycle_timer () {
            apply_timer (timer_seconds == 0 ? 3 : (timer_seconds == 3 ? 10 : 0));
        }

        private void apply_timer (int seconds) {
            timer_seconds = seconds;
            var timer_action = lookup_action ("timer") as SimpleAction;
            if (timer_action != null) timer_action.set_state (new Variant.int32 (seconds));
            timer_bubble.tooltip_text = timer_seconds == 0 ? _("Timer: Off") : _("Timer: %d Seconds").printf (timer_seconds);
            if (timer_seconds > 0) timer_bubble.add_css_class ("camera-timer-on");
            else timer_bubble.remove_css_class ("camera-timer-on");
            show_toast (timer_seconds == 0 ? _("Timer off") : _("Timer %d seconds").printf (timer_seconds));
        }

        private void sync_shutter () {
            if (engine.recording) {
                shutter.add_css_class ("recording");
                shutter.tooltip_text = _("Stop Recording (Space)");
                shutter_time.visible = true;
                if (tick_id == 0) tick_id = Timeout.add (250, () => {
                    int s = (int) engine.recording_seconds ();
                    shutter_time.label = "%d:%02d".printf (s / 60, s % 60);
                    if (!engine.recording) {
                        tick_id = 0;
                        return Source.REMOVE;
                    }
                    return Source.CONTINUE;
                });
            } else {
                shutter.remove_css_class ("recording");
                shutter_time.visible = false;
                shutter.tooltip_text = photo_mode.active ? _("Take a Photo (Space)") : _("Start Recording (Space)");
            }
            if (photo_mode.active) shutter.remove_css_class ("video");
            else shutter.add_css_class ("video");
            photo_mode.sensitive = !engine.recording;
            video_mode.sensitive = !engine.recording;
            set_action_enabled ("mode", stack.visible_child_name == "camera" && !engine.recording);
        }

        private void shoot () {
            if (stack.visible_child_name != "camera" || counting) return;
            if (engine.recording) {
                engine.stop_recording ();
                return;
            }
            if (timer_seconds > 0) {
                int left = timer_seconds;
                counting = true;
                countdown.label = left.to_string ();
                countdown.visible = true;
                Timeout.add (1000, () => {
                    left--;
                    if (left > 0) {
                        countdown.label = left.to_string ();
                        return Source.CONTINUE;
                    }
                    countdown.visible = false;
                    counting = false;
                    act ();
                    return Source.REMOVE;
                });
                return;
            }
            act ();
        }

        private void act () {
            if (photo_mode.active) {
                try {
                    last_path = engine.take_photo (mirror);
                    flash_screen ();
                    update_last ();
                } catch (Error e) {
                    show_toast (e.message);
                }
            } else {
                try {
                    engine.start_recording ();
                } catch (Error e) {
                    show_toast (e.message);
                }
            }
        }

        private void flash_screen () {
            flash.opacity = 1;
            int64 start = -1;
            flash.add_tick_callback ((w, clock) => {
                if (start < 0) start = clock.get_frame_time ();
                double t = (clock.get_frame_time () - start) / 350000.0;
                flash.opacity = double.max (0, 1 - t);
                return t < 1 ? Source.CONTINUE : Source.REMOVE;
            });
        }

        private void find_last () {
            string[] dirs = {
                Path.build_filename (Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir (), "Camera"),
                Path.build_filename (Environment.get_user_special_dir (UserDirectory.VIDEOS) ?? Environment.get_home_dir (), "Camera")
            };
            int64 best = 0;
            foreach (string d in dirs) {
                try {
                    var dir = Dir.open (d);
                    string? n;
                    while ((n = dir.read_name ()) != null) {
                        string p = Path.build_filename (d, n);
                        Posix.Stat st;
                        if (Posix.stat (p, out st) == 0 && (int64) st.st_mtime > best) {
                            best = (int64) st.st_mtime;
                            last_path = p;
                        }
                    }
                } catch (FileError e) {
                }
            }
            update_last ();
        }

        private void update_last () {
            set_action_enabled ("open-last", last_path != null);
            if (last_path == null) {
                last_button.visible = false;
                return;
            }
            last_button.visible = true;
            if (last_path.has_suffix (".jpg")) {
                try {
                    var pix = new Gdk.Pixbuf.from_file_at_scale (last_path, 120, 120, true);
                    last_picture.paintable = Gdk.Texture.for_pixbuf (pix);
                } catch (Error e) {
                }
            } else if (preview.paintable != null) {
                last_picture.paintable = preview.paintable.get_current_image ();
            }
        }

        private void open_folder () {
            string base_dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
            string dir = Path.build_filename (base_dir, "Camera");
            DirUtils.create_with_parents (dir, 0755);
            new FileLauncher (File.new_for_path (dir)).launch.begin (this, null);
        }

        private Label? toast;
        private uint toast_id;

        private void show_toast (string text) {
            if (toast == null) {
                toast = new Label ("");
                toast.add_css_class ("camera-toast");
                toast.halign = Align.CENTER;
                toast.valign = Align.START;
                toast.margin_top = 70;
                toast.wrap = true;
                toast.max_width_chars = 50;
                toast.can_target = false;
                if (overlay != null) overlay.add_overlay (toast);
            }
            toast.label = text;
            toast.visible = true;
            if (toast_id != 0) Source.remove (toast_id);
            toast_id = Timeout.add (2600, () => {
                toast.visible = false;
                toast_id = 0;
                return Source.REMOVE;
            });
        }
    }
}
