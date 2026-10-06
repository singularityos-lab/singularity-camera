int main (string[] args) {
    string dir = GLib.DirUtils.make_tmp ("camera-users-XXXXXX");
    string node = GLib.Path.build_filename (dir, "fakevideo0");
    GLib.FileUtils.set_contents (node, "");
    string prefix = GLib.Path.build_filename (dir, "fakevideo");
    assert (CameraIndicator.CameraUsers.has_devices (prefix));
    int[] none = CameraIndicator.CameraUsers.scan (prefix);
    assert (none.length == 0);
    string[] argv = { "sh", "-c", "exec 3<\"$0\"; exec sleep 5", node };
    GLib.Pid child;
    GLib.Process.spawn_async (null, argv, null, GLib.SpawnFlags.SEARCH_PATH, null, out child);
    GLib.Thread.usleep (500000);
    int[] found = CameraIndicator.CameraUsers.scan (prefix);
    assert (found.length == 1 && found[0] == (int) child);
    var user = CameraIndicator.CameraUsers.describe (found[0]);
    assert (user.name != "");
    Posix.kill (child, Posix.Signal.TERM);
    GLib.Process.close_pid (child);
    GLib.FileUtils.unlink (node);
    GLib.DirUtils.remove (dir);
    print ("camera users: detected pid %d as %s\n", found[0], user.name);
    return 0;
}
