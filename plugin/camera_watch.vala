namespace CameraIndicator {

    public class CameraWatch : GLib.Object {
        private const uint SETTLE_MS = 150;
        private const Linux.InotifyMaskFlags DEVICE_EVENTS = Linux.InotifyMaskFlags.OPEN
            | Linux.InotifyMaskFlags.CLOSE_WRITE | Linux.InotifyMaskFlags.CLOSE_NOWRITE;
        private const Linux.InotifyMaskFlags DIR_EVENTS = Linux.InotifyMaskFlags.CREATE
            | Linux.InotifyMaskFlags.DELETE | Linux.InotifyMaskFlags.MOVED_TO
            | Linux.InotifyMaskFlags.MOVED_FROM;

        private string dir;
        private string base_name;
        private int fd = -1;
        private uint io_id = 0;
        private uint settle_id = 0;
        private Gee.HashSet<string> watched = new Gee.HashSet<string> ();

        public bool complete { get; private set; default = false; }

        public signal void changed ();

        public CameraWatch (string prefix) {
            dir = GLib.Path.get_dirname (prefix);
            base_name = GLib.Path.get_basename (prefix);
            fd = Linux.inotify_init (Linux.InotifyFlags.CLOEXEC | Linux.InotifyFlags.NONBLOCK);
            if (fd < 0) return;
            if (Linux.inotify_add_watch (fd, dir, DIR_EVENTS) < 0) {
                Posix.close (fd);
                fd = -1;
                return;
            }
            io_id = new GLib.IOChannel.unix_new (fd).add_watch (GLib.IOCondition.IN, on_events);
            complete = watch_devices ();
        }

        ~CameraWatch () {
            stop ();
        }

        public void stop () {
            if (settle_id != 0) GLib.Source.remove (settle_id);
            settle_id = 0;
            if (io_id != 0) GLib.Source.remove (io_id);
            io_id = 0;
            if (fd >= 0) Posix.close (fd);
            fd = -1;
        }

        private bool watch_devices () {
            bool all = true;
            var present = new Gee.HashSet<string> ();
            try {
                var d = GLib.Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (!name.has_prefix (base_name)) continue;
                    string path = GLib.Path.build_filename (dir, name);
                    present.add (path);
                    if (watched.contains (path)) continue;
                    if (Linux.inotify_add_watch (fd, path, DEVICE_EVENTS) < 0) {
                        all = false;
                        continue;
                    }
                    watched.add (path);
                }
            } catch (GLib.FileError e) {
                all = false;
            }
            watched.retain_all (present);
            return all;
        }

        private bool on_events (GLib.IOChannel source, GLib.IOCondition condition) {
            uint8 buffer[4096];
            while (Posix.read (fd, buffer, buffer.length) > 0) {}
            complete = watch_devices ();
            if (settle_id == 0) {
                settle_id = GLib.Timeout.add (SETTLE_MS, () => {
                    settle_id = 0;
                    changed ();
                    return GLib.Source.REMOVE;
                });
            }
            return GLib.Source.CONTINUE;
        }
    }
}
