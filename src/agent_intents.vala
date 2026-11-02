namespace Singularity.Apps.Camera {

    internal class CameraIntents : Object {
        private const string NONE = "{\"type\":\"object\",\"properties\":{}}";

        private static CameraWindow window (CameraApp app) throws Error {
            app.activate ();
            var w = app.get_active_window () as CameraWindow;
            if (w == null) throw new IOError.NOT_FOUND ("the camera window is not open");
            return w;
        }

        private static Json.Node path (string? p) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("path").add_string_value (p ?? "");
            b.end_object ();
            return b.get_root ();
        }

        internal static void install (CameraApp app) {
            var agent = app.agent;
            agent.add_intent ("camera_photo", "Take a photo with the open camera, on screen, and return its path.", NONE,
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => path (window (app).agent_photo ()));
            agent.add_intent ("camera_video_start", "Start recording a video, on screen.", NONE,
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    window (app).agent_video (true);
                    return path (null);
                });
            agent.add_intent ("camera_video_stop", "Stop the recording.", NONE,
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    window (app).agent_video (false);
                    return path (null);
                });
            agent.add_intent ("camera_last", "Return the path of the last shot.", NONE,
                Singularity.AppIntentRisk.READ, (args) => path (window (app).agent_last ()));
        }
    }
}
