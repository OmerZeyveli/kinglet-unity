using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace KingletSpike
{
    public static class Probe
    {
        public const string ProjectId = "kinglet-unity-probe";

        [System.Serializable]
        private sealed class PrefBackup
        {
            public bool autoStartPresent;
            public bool autoStart;
            public bool useHttpPresent;
            public bool useHttp;
            public bool scopePresent;
            public string scope;
            public bool urlPresent;
            public string url;
        }

        public static void ConfigureMcpProbe()
        {
            var url = System.Environment.GetEnvironmentVariable("KINGLET_MCP_URL");
            var backupPath = System.Environment.GetEnvironmentVariable("KINGLET_MCP_PREFS_BACKUP");
            if (string.IsNullOrWhiteSpace(url))
                throw new System.InvalidOperationException("KINGLET_MCP_URL is required.");
            if (string.IsNullOrWhiteSpace(backupPath))
                throw new System.InvalidOperationException("KINGLET_MCP_PREFS_BACKUP is required.");
            var backup = new PrefBackup {
                autoStartPresent = EditorPrefs.HasKey("MCPForUnity.AutoStartOnLoad"),
                autoStart = EditorPrefs.GetBool("MCPForUnity.AutoStartOnLoad", false),
                useHttpPresent = EditorPrefs.HasKey("MCPForUnity.UseHttpTransport"),
                useHttp = EditorPrefs.GetBool("MCPForUnity.UseHttpTransport", false),
                scopePresent = EditorPrefs.HasKey("MCPForUnity.HttpTransportScope"),
                scope = EditorPrefs.GetString("MCPForUnity.HttpTransportScope", ""),
                urlPresent = EditorPrefs.HasKey("MCPForUnity.HttpUrl"),
                url = EditorPrefs.GetString("MCPForUnity.HttpUrl", "")
            };
            File.WriteAllText(backupPath, JsonUtility.ToJson(backup) + "\n");
            EditorPrefs.SetBool("MCPForUnity.AutoStartOnLoad", true);
            EditorPrefs.SetBool("MCPForUnity.UseHttpTransport", true);
            EditorPrefs.SetString("MCPForUnity.HttpTransportScope", "local");
            EditorPrefs.SetString("MCPForUnity.HttpUrl", url);
        }

        public static void RestoreMcpProbe()
        {
            var backupPath = System.Environment.GetEnvironmentVariable("KINGLET_MCP_PREFS_BACKUP");
            var backup = JsonUtility.FromJson<PrefBackup>(File.ReadAllText(backupPath));
            RestoreBool("MCPForUnity.AutoStartOnLoad", backup.autoStartPresent, backup.autoStart);
            RestoreBool("MCPForUnity.UseHttpTransport", backup.useHttpPresent, backup.useHttp);
            RestoreString("MCPForUnity.HttpTransportScope", backup.scopePresent, backup.scope);
            RestoreString("MCPForUnity.HttpUrl", backup.urlPresent, backup.url);
        }

        private static void RestoreBool(string key, bool present, bool value)
        {
            if (present) EditorPrefs.SetBool(key, value); else EditorPrefs.DeleteKey(key);
        }

        private static void RestoreString(string key, bool present, string value)
        {
            if (present) EditorPrefs.SetString(key, value); else EditorPrefs.DeleteKey(key);
        }

        [MenuItem("Kinglet Spike/Exit Without Saving")]
        public static void ExitWithoutSaving()
        {
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorApplication.Exit(0);
        }

        [MenuItem("Kinglet Spike/Write Receipt")]
        public static void WriteReceipt()
        {
            var directory = Path.Combine("Library", "KingletSpike");
            Directory.CreateDirectory(directory);
            var json = "{\"schema\":\"kinglet.unity-fixture/v1\","
                + "\"project_id\":\"kinglet-unity-probe\","
                + "\"unity_version\":\"" + Application.unityVersion + "\"}\n";
            File.WriteAllText(Path.Combine(directory, "fixture-receipt.json"), json);
        }
    }
}
