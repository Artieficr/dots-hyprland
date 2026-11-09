import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var sections // [{ title, tasks }], empty sections are skipped
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int listBottomPadding: 80
    signal editRequested(var task)

    // Colors for Obsidian's <mark class="..."> highlights
    readonly property var labelColors: ({
        "blue": "#5b8def", "red": "#e5534b", "teal": "#2fb5a5", "green": "#57ab5a", "yellow": "#c69026",
        "orange": "#e0823d", "purple": "#986ee2", "pink": "#e275ad", "grey": "#8b949e", "gray": "#8b949e"
    })
    // Stable keys, so a file reload only animates rows that really changed, not the whole list
    readonly property var rows: { // Qt's JS engine has no flatMap
        const rows = [];
        const seen = {};
        for (const s of sections) {
            if (s.tasks.length === 0) continue;
            rows.push({ key: `# ${s.title}`, header: s.title, count: s.tasks.length });
            for (const t of s.tasks) {
                const key = `${s.title} ${t.raw}`;
                seen[key] = (seen[key] ?? 0) + 1; // Identical lines
                rows.push({ key: `${key} ${seen[key]}`, task: t });
            }
        }
        return rows;
    }

    function escapeHtml(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Escaped text with **bold**, *italic* and line breaks styled
    function styledText(text) {
        return escapeHtml(text).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/(^|[^*])\*([^*]+)\*/g, "$1<i>$2</i>").replace(/\n/g, "<br>");
    }

    function relativeDate(date) {
        const days = Math.round((new Date(date) - new Date(ObsidianTasks.today)) / 86400000);
        if (days === 0) return Translation.tr("Today");
        if (days === 1) return Translation.tr("Tomorrow");
        if (days === -1) return Translation.tr("Yesterday");
        const [y, m, d] = date.split("-").map(Number);
        return new Date(y, m - 1, d).toLocaleDateString(Qt.locale(), y === new Date().getFullYear() ? "MMM d" : "MMM d, yyyy");
    }

    function longDate(date) {
        const [y, m, d] = date.split("-").map(Number);
        return new Date(y, m - 1, d).toLocaleDateString(Qt.locale(), "ddd, MMM d, yyyy");
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: 5 // animateAppearance stays on: with an empty remove transition, Qt can leave removed rows behind
        bottomMargin: root.listBottomPadding
        model: ScriptModel {
            values: root.rows
            objectProp: "key"
        }
        delegate: Loader {
            id: rowLoader
            required property var modelData
            width: ListView.view.width
            sourceComponent: modelData.header !== undefined ? headerComponent : taskComponent

            Component {
                id: headerComponent
                StyledText {
                    topPadding: 6
                    leftPadding: 4
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: `${rowLoader.modelData.header} · ${rowLoader.modelData.count}`
                }
            }

            Component {
                id: taskComponent
                Rectangle {
                    id: taskItem
                    readonly property var task: rowLoader.modelData.task
                    readonly property var status: ObsidianTasks.statusOf(task)
                    readonly property bool finished: status.type === "DONE" || status.type === "CANCELLED"
                    readonly property var parts: ObsidianTasks.displayParts(task)
                    implicitHeight: taskRow.implicitHeight + 12
                    color: taskHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                    radius: Appearance.rounding.small

                    HoverHandler { // Also counts hover over the text and icons on top
                        id: taskHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.editRequested(taskItem.task)
                    }

                    RowLayout {
                        id: taskRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 4
                            rightMargin: 10
                        }
                        spacing: 6

                        TodoItemActionButton { // Status checkbox: click = next status, like in Obsidian
                            Layout.alignment: Qt.AlignTop
                            tooltipText: taskItem.status.name
                            onClicked: ObsidianTasks.toggle(taskItem.task)
                            contentItem: Item {
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !customSymbol.visible
                                    fill: taskItem.finished ? 1 : 0
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: taskItem.finished ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                                    text: ({ "DONE": "check_box", "CANCELLED": "disabled_by_default", "IN_PROGRESS": "indeterminate_check_box" })[taskItem.status.type] ?? "check_box_outline_blank"
                                }
                                StyledText { // Custom statuses like [!] or [?]
                                    id: customSymbol
                                    anchors.centerIn: parent
                                    visible: taskItem.status.type === "TODO" && taskItem.task.status !== " "
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    text: `[${taskItem.task.status}]`
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                Layout.topMargin: 5
                                wrapMode: Text.Wrap
                                textFormat: Text.StyledText
                                color: taskItem.finished ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                                text: {
                                    const labels = taskItem.parts.labels.map(l => `<font color="${root.labelColors[l.color] ?? Appearance.colors.colPrimary}"><b>${root.escapeHtml(l.text)}</b></font> `).join("");
                                    const body = labels + root.styledText(taskItem.parts.text);
                                    return taskItem.finished ? `<s>${body}</s>` : body;
                                }
                            }

                            Flow { // Priority, dates, recurrence
                                Layout.fillWidth: true
                                spacing: 8
                                visible: metaRepeater.count > 0

                                Repeater {
                                    id: metaRepeater
                                    model: {
                                        const t = taskItem.task;
                                        const items = [];
                                        const priorityIcons = { "highest": "keyboard_double_arrow_up", "high": "keyboard_arrow_up", "medium": "remove", "low": "keyboard_arrow_down", "lowest": "keyboard_double_arrow_down" };
                                        const priorityNames = { "highest": Translation.tr("Highest"), "high": Translation.tr("High"), "medium": Translation.tr("Medium"), "low": Translation.tr("Low"), "lowest": Translation.tr("Lowest") };
                                        if (priorityIcons[t.priority]) items.push({ icon: priorityIcons[t.priority], text: "", tooltip: Translation.tr("Priority: %1").arg(priorityNames[t.priority]) });
                                        if (t.start) items.push({ icon: "flight_takeoff", text: root.relativeDate(t.start), tooltip: Translation.tr("Start: %1").arg(root.longDate(t.start)) });
                                        if (t.scheduled) items.push({ icon: "hourglass_top", text: root.relativeDate(t.scheduled), tooltip: Translation.tr("Scheduled: %1").arg(root.longDate(t.scheduled)) });
                                        if (t.due) items.push({ icon: "event", text: root.relativeDate(t.due), tooltip: Translation.tr("Due: %1").arg(root.longDate(t.due)), late: !taskItem.finished && t.due < ObsidianTasks.today });
                                        if (t.recurrence) items.push({ icon: "repeat", text: t.recurrence, tooltip: Translation.tr("Recurrence: %1").arg(t.recurrence) });
                                        return items;
                                    }
                                    delegate: Item {
                                        id: metaItem
                                        required property var modelData
                                        readonly property bool hovered: metaHover.containsMouse
                                        implicitWidth: metaRow.implicitWidth
                                        implicitHeight: metaRow.implicitHeight

                                        MouseArea { // Hover only, clicks still open the editor
                                            id: metaHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton
                                        }
                                        StyledToolTip {
                                            text: metaItem.modelData.tooltip
                                        }

                                        Row {
                                            id: metaRow
                                            spacing: 2
                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                iconSize: Appearance.font.pixelSize.small
                                                color: metaItem.modelData.late ? Appearance.colors.colError : Appearance.colors.colSubtext
                                                text: metaItem.modelData.icon
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: metaItem.modelData.late ? Appearance.colors.colError : Appearance.colors.colSubtext
                                                text: metaItem.modelData.text
                                            }
                                        }
                                    }
                                }
                            }

                            Item { implicitHeight: 3 }
                        }
                    }
                }
            }
        }
    }

    Item { // Placeholder when empty
        visible: opacity > 0
        opacity: root.rows.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: root.emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: ObsidianTasks.error || root.emptyPlaceholderText
            }
        }
    }
}
