using Gtk;

namespace Singularity.Apps.Camera {

    public class CameraApp : Singularity.Application {
        public CameraApp () {
            Object (application_id: "dev.sinty.camera", flags: ApplicationFlags.DEFAULT_FLAGS);
            force_dark = true;
            add_main_option ("photo", 0, OptionFlags.NONE, OptionArg.NONE, _("Open in photo mode"), null);
            add_main_option ("video", 0, OptionFlags.NONE, OptionArg.NONE, _("Open in video mode"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            string? mode = null;
            if (options.contains ("photo")) mode = "photo";
            else if (options.contains ("video")) mode = "video";
            if (mode == null) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("camera: %s", e.message);
                return 1;
            }
            activate_action ("open-mode", new Variant.string (mode));
            return get_is_remote () ? 0 : -1;
        }

        protected override void startup () {
            base.startup ();
            IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/dev/sinty/camera/icons");
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("Open Last Shot"), "win.open-last");
            f1.append (_("Open Camera Folder"), "win.open-folder");
            file.append_section (null, f1);
            var f2 = new GLib.Menu ();
            f2.append (_("Close Window"), "win.close");
            f2.append (_("Quit"), "app.quit");
            file.append_section (null, f2);
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            edit.append (_("Settings"), "app.settings");
            menu.append_submenu (_("Edit"), edit);
            var view = new GLib.Menu ();
            view.append (_("Fullscreen"), "win.fullscreen");
            menu.append_submenu (_("View"), view);
            var camera = new GLib.Menu ();
            var c1 = new GLib.Menu ();
            c1.append (_("Capture"), "win.shoot");
            c1.append (_("Photo"), "win.mode::photo");
            c1.append (_("Video"), "win.mode::video");
            camera.append_section (null, c1);
            var c2 = new GLib.Menu ();
            var timer = new GLib.Menu ();
            timer.append (_("Off"), "win.timer(0)");
            timer.append (_("3 Seconds"), "win.timer(3)");
            timer.append (_("10 Seconds"), "win.timer(10)");
            c2.append_submenu (_("Timer"), timer);
            c2.append (_("Mirror Preview"), "win.mirror");
            camera.append_section (null, c2);
            var c3 = new GLib.Menu ();
            c3.append (_("Switch Camera"), "win.switch-camera");
            c3.append (_("Look for Cameras Again"), "win.rescan");
            camera.append_section (null, c3);
            menu.append_submenu (_("Camera"), camera);
            set_menubar (menu);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ()) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.camera");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            var open_mode = new SimpleAction ("open-mode", VariantType.STRING);
            open_mode.activate.connect ((param) => {
                activate ();
                var w = get_active_window () as CameraWindow;
                if (w != null) w.select_mode (param.get_string ());
            });
            add_action (open_mode);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.fullscreen", { "F11" });
            set_accels_for_action ("win.mirror", { "<Control>m" });
        }

        public override void activate () {
            var w = get_active_window ();
            if (w == null) w = new CameraWindow (this);
            w.present ();
        }

        private const string CSS = """
.camera-stage {
    background-color: #0b0c0f;
}

.camera-preview.mirrored {
    transform: scaleX(-1);
}

.camera-flash {
    background-color: white;
}

.camera-qr-pill {
    background-color: alpha(black, 0.62);
    color: white;
    border-radius: 999px;
    padding: 6px 6px 6px 14px;
}

.camera-live-text {
    background-color: alpha(black, 0.62);
    color: white;
    border-radius: 999px;
    min-width: 40px;
    min-height: 40px;
}

.camera-live-text:checked {
    background-color: white;
}

.camera-live-text:checked image {
    color: #0b0c0f;
    -gtk-icon-style: symbolic;
}

.camera-countdown {
    font-size: 120px;
    font-weight: 800;
    color: white;
    text-shadow: 0 4px 24px alpha(black, 0.6);
}

.camera-bar {
    padding: 12px 18px;
    border-radius: 28px;
    background-color: alpha(black, 0.35);
}

.camera-shutter {
    min-width: 68px;
    min-height: 68px;
    padding: 0;
    border-radius: 99px;
    background: transparent;
    border: 4px solid white;
    box-shadow: 0 4px 16px alpha(black, 0.4);
}

.camera-shutter-inner {
    min-width: 50px;
    min-height: 50px;
    border-radius: 99px;
    background-color: white;
    transition: all 150ms ease;
}

.camera-shutter:hover .camera-shutter-inner {
    background-color: alpha(white, 0.85);
}

.camera-shutter.video .camera-shutter-inner {
    background-color: #e01b24;
}

.camera-shutter.recording .camera-shutter-inner {
    min-width: 26px;
    min-height: 26px;
    border-radius: 6px;
    background-color: #e01b24;
}

.camera-time {
    color: white;
    font-feature-settings: "tnum";
    font-weight: 700;
}

.camera-modes button.camera-mode,
.camera-modes button.camera-mode label {
    color: alpha(white, 0.85);
}

.camera-modes button.camera-mode {
    background: transparent;
    border-radius: 99px;
    padding: 2px 12px;
    font-weight: 700;
    box-shadow: none;
    border: none;
    min-height: 0;
}

.camera-modes button.camera-mode:hover {
    background-color: alpha(white, 0.12);
}

.camera-modes button.camera-mode:checked {
    background-color: alpha(white, 0.92);
}

.camera-modes button.camera-mode:checked label {
    color: black;
}

.camera-round {
    min-width: 46px;
    min-height: 46px;
    border-radius: 99px;
    color: white;
    background-color: alpha(white, 0.15);
    border: none;
}

.camera-last {
    padding: 0;
    border-radius: 14px;
    border: 2px solid alpha(white, 0.85);
    background-color: alpha(black, 0.3);
}

.camera-toast {
    padding: 8px 16px;
    border-radius: 18px;
    background-color: alpha(black, 0.7);
    color: white;
}

.camera-timer-on {
    background-color: @accent_bg_color;
    color: white;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        Gst.init (ref args);
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-camera", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-camera", "UTF-8");
        Intl.textdomain ("singularity-camera");
        return new CameraApp ().run (args);
    }
}
