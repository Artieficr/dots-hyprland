pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick
import "obsidian_tasks.js" as Lib

/**
 * Obsidian Tasks bridge: reads and edits a Markdown tasks file in the Tasks plugin's emoji format.
 * The file is watched, and every write re-reads it and replaces only the affected line, so edits
 * made in Obsidian at the same time aren't lost. Tasks plugin settings (global filter, statuses,
 * auto dates, recurrence placement) are read from the vault's plugin data when found.
 */
Singleton {
    id: root
    readonly property bool enabled: Config.options.sidebar.obsidianTasks.enable
    readonly property string filePath: {
        const path = Config.options.sidebar.obsidianTasks.path.trim();
        return path.startsWith("~") ? FileUtils.trimFileProtocol(Directories.home) + path.slice(1) : path;
    }
    property var settings: Lib.DEFAULT_SETTINGS
    property var tasks: []
    property string today: Lib.localToday()
    property string error: ""
    readonly property var sections: Lib.sections(tasks, today, settings)
    // Reminders, Today and Overdue, like the daily note's top part
    readonly property var todayTasks: [...sections.reminders, ...sections.today, ...sections.overdue.filter(t => !sections.today.includes(t))]
    readonly property int openCount: tasks.filter(t => Lib.isOpen(t, settings)).length

    function displayParts(task) { return Lib.displayParts(task.description); }
    function plainText(task) { return Lib.plainText(task.description); }
    function statusOf(task) { return Lib.statusOf(task.status, settings); }
    function editableDescription(task) { return Lib.editableDescription(task, settings); }
    function parseDateInput(text) { return Lib.parseDateInput(text, today); }
    function isRuleSupported(text) { return text.trim() === "" || Lib.parseRule(text) !== null; }

    // Checkbox click. Returns false if it can't be done here (unsupported recurrence rule)
    function toggle(task) {
        const lines = Lib.toggled(task, today, settings);
        if (!lines) return refuse(Translation.tr("Complete this recurring task in Obsidian: \"%1\" isn't supported here").arg(task.recurrence));
        return replaceLine(task, lines);
    }

    function setStatus(task, symbol) {
        if (symbol === task.status) return true;
        const lines = Lib.withStatus(task, symbol, today, settings);
        if (!lines) return refuse(Translation.tr("Complete this recurring task in Obsidian: \"%1\" isn't supported here").arg(task.recurrence));
        return replaceLine(task, lines);
    }

    // fields: description (without global filter), priority, recurrence, start, scheduled, due.
    // A status change is applied in the same write, with its done/cancelled dates and recurrence
    function save(task, fields, statusSymbol) {
        const edited = Lib.parseLine(Lib.withEditedFields(task, fields, settings), task.line, settings);
        const lines = Lib.withStatus(edited, statusSymbol, today, settings);
        if (!lines) return refuse(Translation.tr("Complete this recurring task in Obsidian: \"%1\" isn't supported here").arg(fields.recurrence));
        return replaceLine(task, lines);
    }

    function remove(task) {
        return replaceLine(task, []);
    }

    // New tasks go first, right after the frontmatter (the file is newest-first)
    function add(fields) {
        const lines = tasksFile.text().split("\n");
        let at = 0;
        if (lines[0] === "---") at = lines.indexOf("---", 1) + 1;
        lines.splice(at, 0, Lib.newTaskLine(fields, today, settings));
        tasksFile.setText(lines.join("\n"));
        return true;
    }

    function replaceLine(task, newLines) {
        const lines = tasksFile.text().split("\n");
        let at = lines[task.line] === task.raw ? task.line : lines.indexOf(task.raw);
        if (at < 0) return refuse(Translation.tr("The tasks file changed in the meantime, try again"));
        lines.splice(at, 1, ...newLines);
        tasksFile.setText(lines.join("\n"));
        return true;
    }

    function refuse(message) {
        Quickshell.execDetached(["notify-send", Translation.tr("Obsidian Tasks"), message, "-a", "Shell"]);
        return false;
    }

    Timer { // Keep "today" right across midnight
        running: root.enabled
        interval: 60000
        repeat: true
        onTriggered: root.today = Lib.localToday()
    }

    FileView {
        id: tasksFile
        path: root.enabled ? root.filePath : ""
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            root.error = "";
            root.tasks = Lib.parseFile(tasksFile.text(), root.settings);
        }
        onLoadFailed: error => {
            root.error = Translation.tr("Can't read %1").arg(root.filePath);
            root.tasks = [];
        }
    }

    Process { // Tasks plugin settings from <vault>/.obsidian, found by walking up from the file
        running: root.enabled && root.filePath !== ""
        command: ["bash", "-c", `d=$(dirname "$1"); while [ "$d" != / ]; do f="$d/.obsidian/plugins/obsidian-tasks-plugin/data.json"; [ -f "$f" ] && exec cat "$f"; d=$(dirname "$d"); done`, "_", root.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!this.text.trim()) return;
                try {
                    root.settings = Lib.settingsFromPluginData(JSON.parse(this.text));
                    root.tasks = Lib.parseFile(tasksFile.text(), root.settings); // The global filter may have changed
                } catch (e) {
                    console.log("[ObsidianTasks] Couldn't read Tasks plugin settings: " + e);
                }
            }
        }
    }
}
