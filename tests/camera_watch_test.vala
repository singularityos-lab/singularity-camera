bool wait_for_change (CameraIndicator.CameraWatch watch, ref int seen, int before) {
    var loop = new GLib.MainLoop ();
    uint timeout = GLib.Timeout.add (2000, () => {
        loop.quit ();
        return GLib.Source.REMOVE;
    });
    ulong id = watch.changed.connect (() => loop.quit ());
    loop.run ();
    watch.disconnect (id);
    GLib.Source.remove (timeout);
    return seen > before;
}

int main (string[] args) {
    string dir = GLib.DirUtils.make_tmp ("camera-watch-XXXXXX");
    string first = GLib.Path.build_filename (dir, "fakevideo0");
    GLib.FileUtils.set_contents (first, "");
    var watch = new CameraIndicator.CameraWatch (GLib.Path.build_filename (dir, "fakevideo"));
    assert (watch.complete);
    int seen = 0;
    watch.changed.connect (() => seen++);

    var stream = GLib.FileStream.open (first, "r");
    stream = null;
    assert (wait_for_change (watch, ref seen, 0));
    int after_open = seen;

    var quiet = new GLib.MainLoop ();
    GLib.Timeout.add (600, () => {
        quiet.quit ();
        return GLib.Source.REMOVE;
    });
    quiet.run ();
    assert (seen == after_open);

    string second = GLib.Path.build_filename (dir, "fakevideo1");
    GLib.FileUtils.set_contents (second, "");
    assert (wait_for_change (watch, ref seen, after_open));
    int after_plug = seen;

    stream = GLib.FileStream.open (second, "r");
    stream = null;
    assert (wait_for_change (watch, ref seen, after_plug));

    GLib.FileUtils.set_contents (GLib.Path.build_filename (dir, "other"), "");
    watch.stop ();
    GLib.FileUtils.unlink (GLib.Path.build_filename (dir, "other"));
    GLib.FileUtils.unlink (second);
    GLib.FileUtils.unlink (first);
    GLib.DirUtils.remove (dir);
    print ("camera watch: %d changes, none while idle\n", seen);
    return 0;
}
