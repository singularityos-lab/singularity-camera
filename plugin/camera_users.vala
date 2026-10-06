namespace CameraIndicator {

    public class CameraUser : GLib.Object {
        public int pid;
        public string name = "";
        public GLib.Icon? icon = null;
        public string desktop_id = "";
    }

    public class CameraUsers : GLib.Object {
        public static bool has_devices (string prefix) {
            string dir = GLib.Path.get_dirname (prefix);
            string base_name = GLib.Path.get_basename (prefix);
            try {
                var d = GLib.Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (name.has_prefix (base_name)) return true;
                }
            } catch (GLib.FileError e) {}
            return false;
        }

        public static int[] scan (string prefix) {
            int[] pids = {};
            int self = Posix.getpid ();
            try {
                var proc = GLib.Dir.open ("/proc");
                string? entry;
                while ((entry = proc.read_name ()) != null) {
                    if (!entry.get_char (0).isdigit ()) continue;
                    int pid = int.parse (entry);
                    if (pid == self) continue;
                    string fd_dir = "/proc/%s/fd".printf (entry);
                    GLib.Dir fds;
                    try {
                        fds = GLib.Dir.open (fd_dir);
                    } catch (GLib.FileError e) {
                        continue;
                    }
                    string? fd;
                    while ((fd = fds.read_name ()) != null) {
                        string target;
                        try {
                            target = GLib.FileUtils.read_link (fd_dir + "/" + fd);
                        } catch (GLib.FileError e) {
                            continue;
                        }
                        if (target.has_prefix (prefix)) {
                            pids += pid;
                            break;
                        }
                    }
                }
            } catch (GLib.FileError e) {}
            return pids;
        }

        public static CameraUser describe (int pid) {
            var user = new CameraUser ();
            user.pid = pid;
            GLib.DesktopAppInfo? info = null;
            try {
                uint8[] environ;
                GLib.FileUtils.get_data ("/proc/%d/environ".printf (pid), out environ);
                int start = 0;
                for (int i = 0; i < environ.length; i++) {
                    if (environ[i] != 0) continue;
                    string item = (string) environ[start:i];
                    start = i + 1;
                    if (item.has_prefix ("GIO_LAUNCHED_DESKTOP_FILE=")) {
                        info = new GLib.DesktopAppInfo.from_filename (item.substring ("GIO_LAUNCHED_DESKTOP_FILE=".length));
                        break;
                    }
                }
            } catch (GLib.FileError e) {}
            string comm = "";
            try {
                GLib.FileUtils.get_contents ("/proc/%d/comm".printf (pid), out comm);
                comm = comm.strip ();
            } catch (GLib.FileError e) {}
            string exe_name = comm;
            try {
                exe_name = GLib.Path.get_basename (GLib.FileUtils.read_link ("/proc/%d/exe".printf (pid)));
            } catch (GLib.FileError e) {}
            if (info == null && exe_name != "") info = find_app (exe_name);
            if (comm == "") comm = exe_name;
            if (info != null) {
                user.name = info.get_display_name ();
                user.icon = info.get_icon ();
                user.desktop_id = info.get_id () ?? "";
            } else {
                user.name = comm != "" ? comm : _("Unknown app");
            }
            return user;
        }

        public static bool is_media_server (int pid) {
            string comm = "";
            try {
                GLib.FileUtils.get_contents ("/proc/%d/comm".printf (pid), out comm);
            } catch (GLib.FileError e) {
                return false;
            }
            comm = comm.strip ();
            return comm == "pipewire" || comm == "wireplumber" || comm == "pipewire-media-session";
        }

        public static CameraUser describe_client (Singularity.CameraClient client) {
            if (client.app_id != null) {
                var info = new GLib.DesktopAppInfo (client.app_id + ".desktop");
                if (info != null) {
                    var user = new CameraUser ();
                    user.pid = client.pid;
                    user.name = info.get_display_name ();
                    user.icon = info.get_icon ();
                    user.desktop_id = info.get_id () ?? "";
                    return user;
                }
            }
            if (client.pid > 0 && GLib.FileUtils.test ("/proc/%d".printf (client.pid), GLib.FileTest.IS_DIR)) {
                var user = describe (client.pid);
                if (user.desktop_id != "" || client.name == "") return user;
            }
            var user = new CameraUser ();
            user.pid = client.pid;
            if (client.binary != null) {
                var info = find_app (client.binary);
                if (info != null) {
                    user.name = info.get_display_name ();
                    user.icon = info.get_icon ();
                    user.desktop_id = info.get_id () ?? "";
                    return user;
                }
            }
            user.name = client.name != "" ? client.name : _("Unknown app");
            return user;
        }

        private static GLib.DesktopAppInfo? find_app (string comm) {
            var direct = new GLib.DesktopAppInfo (comm + ".desktop");
            if (direct != null) return direct;
            foreach (var app in GLib.AppInfo.get_all ()) {
                string? exe = app.get_executable ();
                if (exe != null && GLib.Path.get_basename (exe) == comm) return app as GLib.DesktopAppInfo;
            }
            return null;
        }
    }
}
