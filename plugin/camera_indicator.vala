[ModuleInit]
public void peas_register_types (GLib.TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (Singularity.Plugin), typeof (CameraIndicatorPlugin));
}

namespace CameraIndicator {

    public class Indicator : Gtk.Box {
        private const string DEVICE_PREFIX = "/dev/video";
        private uint poll_id = 0;
        private string last_key = "";
        private Gtk.Box list;
        private Gtk.MenuButton button;

        public Indicator () {
            button = new Gtk.MenuButton ();
            button.add_css_class ("flat");
            button.add_css_class ("panel-button");
            append (button);
            visible = false;
            button.tooltip_text = _("Camera in use");

            var dot = new Gtk.DrawingArea ();
            dot.content_width = 10;
            dot.content_height = 10;
            dot.valign = Gtk.Align.CENTER;
            dot.set_draw_func ((area, cr, w, h) => {
                cr.arc (w / 2.0, h / 2.0, double.min (w, h) / 2.0, 0, 2 * Math.PI);
                cr.set_source_rgb (0.96, 0.47, 0.0);
                cr.fill ();
            });
            var icon = new Gtk.Image.from_icon_name ("camera-web-symbolic");
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.append (dot);
            box.append (icon);
            button.child = box;

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            content.margin_start = 12;
            content.margin_end = 12;
            content.margin_top = 10;
            content.margin_bottom = 10;
            var title = new Gtk.Label (_("Camera in use"));
            title.add_css_class ("heading");
            title.xalign = 0;
            content.append (title);
            list = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            content.append (list);
            var pop = new Gtk.Popover ();
            pop.child = content;
            button.popover = pop;

            poll ();
            poll_id = GLib.Timeout.add_seconds (3, () => {
                poll ();
                return GLib.Source.CONTINUE;
            });
        }

        public void stop () {
            if (poll_id != 0) GLib.Source.remove (poll_id);
            poll_id = 0;
        }

        private void poll () {
            if (!CameraUsers.has_devices (DEVICE_PREFIX)) {
                update ({});
                return;
            }
            new GLib.Thread<void> ("camera-indicator", () => {
                int[] direct = {};
                bool through_server = false;
                foreach (int pid in CameraUsers.scan (DEVICE_PREFIX)) {
                    if (CameraUsers.is_media_server (pid)) through_server = true;
                    else direct += pid;
                }
                GLib.Idle.add (() => {
                    collect.begin (direct, through_server);
                    return GLib.Source.REMOVE;
                });
            });
        }

        private async void collect (int[] direct, bool through_server) {
            CameraUser[] users = {};
            foreach (int pid in direct) users += CameraUsers.describe (pid);
            if (through_server) {
                foreach (var client in yield Singularity.CameraClients.query ()) users += CameraUsers.describe_client (client);
            }
            update (users);
        }

        private void update (CameraUser[] users) {
            string key = "";
            foreach (var user in users) key += "%d:%s,".printf (user.pid, user.name);
            if (key == last_key) return;
            last_key = key;
            visible = users.length > 0;
            var child = list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                list.remove (child);
                child = next;
            }
            var seen = new Gee.HashSet<string> ();
            foreach (var user in users) {
                if (!seen.add (user.name)) continue;
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                var image = user.icon != null ? new Gtk.Image.from_gicon (user.icon) : new Gtk.Image.from_icon_name ("application-x-executable");
                image.pixel_size = 32;
                row.append (image);
                var label = new Gtk.Label (user.name);
                label.xalign = 0;
                label.hexpand = true;
                row.append (label);
                list.append (row);
            }
            if (users.length > 0) {
                string[] names = {};
                foreach (var s in seen) names += s;
                button.tooltip_text = _("Camera in use by %s").printf (string.joinv (", ", names));
            }
        }
    }
}

public class CameraIndicatorPlugin : GLib.Object, Singularity.Plugin {
    private Singularity.PluginContext? context = null;
    private CameraIndicator.Indicator? indicator = null;

    public void activate (Singularity.PluginContext context) {
        this.context = context;
        indicator = new CameraIndicator.Indicator ();
        context.add_panel_widget (indicator, Gtk.Align.END);
    }

    public void deactivate () {
        if (indicator != null) {
            indicator.stop ();
            if (context != null) context.remove_panel_widget (indicator);
        }
        indicator = null;
        context = null;
    }

    public Gtk.Widget? get_settings_widget () {
        return null;
    }
}
