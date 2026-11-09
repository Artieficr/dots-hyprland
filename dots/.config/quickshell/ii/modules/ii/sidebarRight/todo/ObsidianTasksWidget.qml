import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// To Do tab backed by an Obsidian Tasks file (Settings > Interface > Sidebars)
Item {
    id: root
    property var tabButtonList: [
        { "icon": "today", "name": Translation.tr("Today") },
        { "icon": "upcoming", "name": Translation.tr("Upcoming") },
        { "icon": "check_circle", "name": Translation.tr("Done") }
    ]
    property bool showDialog: false
    property var editingTask: null // null = adding
    property var pickerTarget: null // DateField the date picker is open for
    property int dialogMargins: 16
    property int fabSize: 40 // Smaller than the built-in to-do's, the task list area is small
    property int fabMargins: 10
    readonly property var priorities: [
        { "name": Translation.tr("No priority"), "value": "none" },
        { "name": Translation.tr("Highest"), "value": "highest" },
        { "name": Translation.tr("High"), "value": "high" },
        { "name": Translation.tr("Medium"), "value": "medium" },
        { "name": Translation.tr("Low"), "value": "low" },
        { "name": Translation.tr("Lowest"), "value": "lowest" }
    ]

    function openDialog(task) {
        root.editingTask = task;
        descriptionInput.text = task ? ObsidianTasks.editableDescription(task) : "";
        statusBox.currentIndex = task ? Math.max(0, ObsidianTasks.settings.statuses.findIndex(s => s.symbol === task.status)) : 0;
        priorityBox.currentIndex = task ? Math.max(0, root.priorities.findIndex(p => p.value === task.priority)) : 0;
        startField.text = task?.start ?? "";
        scheduledField.text = task?.scheduled ?? "";
        dueField.text = task?.due ?? "";
        recurrenceInput.text = task?.recurrence ?? "";
        root.showDialog = true;
    }

    function openPicker(field) {
        datePicker.value = field.value ?? "";
        datePicker.showMonthOf(field.value);
        root.pickerTarget = field;
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) tabBar.incrementCurrentIndex();
            else tabBar.decrementCurrentIndex();
            event.accepted = true;
        } else if (event.key === Qt.Key_N && !root.showDialog) {
            root.openDialog(null);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.pickerTarget) {
            root.pickerTarget = null;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.showDialog) {
            root.showDialog = false;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: tabBar.currentIndex

            ObsidianTaskList { // Same queries as the daily note
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing for today!")
                sections: [
                    { title: Translation.tr("Reminders"), tasks: ObsidianTasks.sections.reminders },
                    { title: Translation.tr("Today"), tasks: ObsidianTasks.sections.today },
                    { title: Translation.tr("Overdue"), tasks: ObsidianTasks.sections.overdue },
                    { title: Translation.tr("Unscheduled"), tasks: ObsidianTasks.sections.unscheduled }
                ]
                onEditRequested: task => root.openDialog(task)
            }
            ObsidianTaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "upcoming"
                emptyPlaceholderText: Translation.tr("Nothing planned")
                sections: [{ title: Translation.tr("Upcoming"), tasks: ObsidianTasks.sections.upcoming }]
                onEditRequested: task => root.openDialog(task)
            }
            ObsidianTaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Tasks done or cancelled today\nwill go here")
                sections: [{ title: Translation.tr("Done/Cancelled today"), tasks: ObsidianTasks.sections.done }]
                onEditRequested: task => root.openDialog(task)
            }
        }
    }

    // + FAB
    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: fabButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins

        baseSize: root.fabSize
        onClicked: root.openDialog(null)
        iconText: "add"
    }

    component DialogTextField: TextField {
        id: textField
        Layout.fillWidth: true
        padding: 8
        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
        renderType: Text.NativeRendering
        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
        selectionColor: Appearance.colors.colSecondaryContainer
        placeholderTextColor: Appearance.m3colors.m3outline

        background: Rectangle {
            radius: Appearance.rounding.verysmall
            border.width: textField.activeFocus ? 2 : 1
            border.color: textField.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
            color: "transparent"
        }
    }

    // Date input: YYYY-MM-DD or today, tomorrow, friday, +3d, +2w, +1m. Shows what it resolves to
    component DateField: RowLayout {
        id: dateField
        property alias text: dateInput.text
        property string icon
        property string label
        readonly property var value: ObsidianTasks.parseDateInput(dateInput.text) // null = invalid
        signal accepted()
        signal pickRequested()
        spacing: 6

        MaterialSymbol {
            readonly property bool hovered: dateIconHover.containsMouse
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
            text: dateField.icon
            MouseArea {
                id: dateIconHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            StyledToolTip {
                text: dateField.label
            }
        }
        DialogTextField {
            id: dateInput
            placeholderText: dateField.label
            onAccepted: dateField.accepted()
        }
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            onClicked: dateField.pickRequested()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "calendar_month"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
        }
        StyledText {
            Layout.preferredWidth: 72
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: dateField.value === null ? Appearance.colors.colError : Appearance.colors.colSubtext
            text: {
                if (dateField.value === null) return Translation.tr("Invalid date");
                if (dateField.value === "") return "";
                const [y, m, d] = dateField.value.split("-").map(Number);
                return new Date(y, m - 1, d).toLocaleDateString(Qt.locale(), "ddd, MMM d");
            }
        }
    }

    Item {
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.showDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) fabButton.focus = true;
        }

        Rectangle { // Scrim
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
                onClicked: root.showDialog = false
            }
        }

        Rectangle { // The dialog
            id: dialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: Math.min(dialogColumn.implicitHeight, parent.height - root.dialogMargins * 2)
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            readonly property bool valid: descriptionInput.text.trim().length > 0
                && startField.value !== null && scheduledField.value !== null && dueField.value !== null

            function save() {
                if (!valid) return;
                const fields = {
                    description: descriptionInput.text.replace(/\n/g, " ").trim(),
                    priority: root.priorities[priorityBox.currentIndex].value,
                    recurrence: recurrenceInput.text.trim(),
                    start: startField.value,
                    scheduled: scheduledField.value,
                    due: dueField.value
                };
                const ok = root.editingTask
                    ? ObsidianTasks.save(root.editingTask, fields, ObsidianTasks.settings.statuses[statusBox.currentIndex].symbol)
                    : ObsidianTasks.add(fields);
                if (ok) root.showDialog = false;
            }

            MouseArea { // Keep clicks inside from closing the dialog
                anchors.fill: parent
            }

            ColumnLayout {
                id: dialogColumn
                anchors.fill: parent
                spacing: 0

                StyledText {
                    Layout.margins: 16
                    Layout.bottomMargin: 10
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: root.editingTask ? Translation.tr("Edit task") : Translation.tr("Add task")
                }

                Flickable { // Scrolls when the sidebar is short
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: fieldsColumn.implicitHeight
                    contentHeight: fieldsColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: fieldsColumn
                        width: parent.width
                        spacing: 8

                        TextArea {
                            id: descriptionInput
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            padding: 8
                            wrapMode: TextEdit.Wrap
                            focus: root.showDialog
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            renderType: Text.NativeRendering
                            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                            selectionColor: Appearance.colors.colSecondaryContainer
                            placeholderText: Translation.tr("Task description (Markdown, #tags)")
                            placeholderTextColor: Appearance.m3colors.m3outline
                            Keys.onReturnPressed: event => dialog.save() // Tasks are single lines
                            Keys.onEnterPressed: event => dialog.save()

                            background: Rectangle {
                                radius: Appearance.rounding.verysmall
                                border.width: descriptionInput.activeFocus ? 2 : 1
                                border.color: descriptionInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                                color: "transparent"
                            }
                        }

                        RowLayout {
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            spacing: 6

                            StyledComboBox {
                                id: statusBox
                                Layout.fillWidth: true
                                visible: root.editingTask !== null
                                buttonIcon: "check_box"
                                textRole: "name"
                                model: ObsidianTasks.settings.statuses
                            }
                            StyledComboBox {
                                id: priorityBox
                                Layout.fillWidth: true
                                buttonIcon: "flag"
                                textRole: "name"
                                model: root.priorities
                            }
                        }

                        ColumnLayout {
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            spacing: 6

                            DateField {
                                id: scheduledField
                                onAccepted: dialog.save()
                                onPickRequested: root.openPicker(scheduledField)
                                icon: "hourglass_top"
                                label: Translation.tr("Scheduled")
                            }
                            DateField {
                                id: dueField
                                onAccepted: dialog.save()
                                onPickRequested: root.openPicker(dueField)
                                icon: "event"
                                label: Translation.tr("Due")
                            }
                            DateField {
                                id: startField
                                onAccepted: dialog.save()
                                onPickRequested: root.openPicker(startField)
                                icon: "flight_takeoff"
                                label: Translation.tr("Start")
                            }

                            RowLayout {
                                spacing: 6
                                MaterialSymbol {
                                    readonly property bool hovered: repeatIconHover.containsMouse
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                    text: "repeat"
                                    MouseArea {
                                        id: repeatIconHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Recurrence")
                                    }
                                }
                                DialogTextField {
                                    id: recurrenceInput
                                    placeholderText: Translation.tr("Recurrence, e.g. every week")
                                    onAccepted: dialog.save()
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: !ObsidianTasks.isRuleSupported(recurrenceInput.text)
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colError
                                text: Translation.tr("This rule can only be completed in Obsidian")
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.margins: 16
                    Layout.topMargin: 12
                    spacing: 5

                    DialogButton {
                        visible: root.editingTask !== null
                        buttonText: Translation.tr("Delete")
                        colEnabled: Appearance.colors.colError
                        onClicked: {
                            if (ObsidianTasks.remove(root.editingTask)) root.showDialog = false;
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showDialog = false
                    }
                    DialogButton {
                        buttonText: root.editingTask ? Translation.tr("Save") : Translation.tr("Add")
                        enabled: dialog.valid
                        onClicked: dialog.save()
                    }
                }
            }
        }
    }

    Item { // Date picker, above the dialog
        anchors.fill: parent
        z: 10000
        visible: opacity > 0
        opacity: root.pickerTarget ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Rectangle { // Scrim
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                anchors.fill: parent
                onClicked: root.pickerTarget = null
            }
        }

        ObsidianDatePicker {
            id: datePicker
            anchors.centerIn: parent
            onPicked: date => {
                root.pickerTarget.text = date;
                root.pickerTarget = null;
            }
            onDismissed: root.pickerTarget = null
        }
    }
}
