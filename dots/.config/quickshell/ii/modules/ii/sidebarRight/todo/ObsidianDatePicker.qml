import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// Month grid for picking a "YYYY-MM-DD" date, sized to fit the sidebar's bottom group
Rectangle {
    id: root
    property string value // Selected date, "" = none
    property int viewYear
    property int viewMonth // 0-based
    signal picked(string date) // "" = cleared
    signal dismissed()

    color: Appearance.m3colors.m3surfaceContainerHigh
    radius: Appearance.rounding.normal
    implicitWidth: pickerColumn.implicitWidth + 20
    implicitHeight: pickerColumn.implicitHeight + 20

    function pad(n) { return n.toString().padStart(2, "0"); }
    function format(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }
    function showMonthOf(date) {
        const [y, m] = (date || ObsidianTasks.today).split("-").map(Number);
        root.viewYear = y;
        root.viewMonth = m - 1;
    }
    function shiftMonth(n) {
        const d = new Date(root.viewYear, root.viewMonth + n, 1);
        root.viewYear = d.getFullYear();
        root.viewMonth = d.getMonth();
    }

    // 6 weeks starting on Monday, like the sidebar calendar
    readonly property var cells: {
        const offset = (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7;
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(viewYear, viewMonth, 1 - offset + i);
            cells.push({ date: format(d), day: d.getDate(), inMonth: d.getMonth() === viewMonth });
        }
        return cells;
    }

    MouseArea { // Scroll to change month; also keeps clicks from reaching what's below
        anchors.fill: parent
        onWheel: event => root.shiftMonth(event.angleDelta.y > 0 ? -1 : 1)
    }

    ColumnLayout {
        id: pickerColumn
        anchors.centerIn: parent
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
                text: new Date(root.viewYear, root.viewMonth, 1).toLocaleDateString(Qt.locale(), "MMMM yyyy")
            }
            Repeater {
                model: [{ icon: "chevron_left", step: -1 }, { icon: "chevron_right", step: 1 }]
                delegate: RippleButton {
                    required property var modelData
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.shiftMonth(modelData.step)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        GridLayout {
            columns: 7
            rowSpacing: 2
            columnSpacing: 2

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                delegate: StyledText {
                    required property string modelData
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    text: Translation.tr(modelData)
                }
            }
            Repeater {
                model: root.cells
                delegate: RippleButton {
                    id: dayButton
                    required property var modelData
                    readonly property bool selected: modelData.date === root.value
                    readonly property bool isToday: modelData.date === ObsidianTasks.today
                    implicitWidth: 30
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.small
                    toggled: selected
                    onClicked: root.picked(modelData.date)
                    contentItem: StyledText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: dayButton.isToday ? Font.Bold : Font.Normal
                        font.underline: dayButton.isToday
                        color: dayButton.selected ? Appearance.m3colors.m3onPrimary
                            : dayButton.isToday ? Appearance.colors.colPrimary
                            : dayButton.modelData.inMonth ? Appearance.colors.colOnLayer1 : Appearance.colors.colOutlineVariant
                        text: dayButton.modelData.day
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            DialogButton {
                buttonText: Translation.tr("Clear")
                onClicked: root.picked("")
            }
            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                buttonText: Translation.tr("Today")
                onClicked: root.picked(ObsidianTasks.today)
            }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: root.dismissed()
            }
        }
    }
}
