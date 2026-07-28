// Minimal quickshell config for smoke-testing a prebuilt package.
//
//   quickshell -p shell.qml
//   quickshell -p /path/to/examples/hello/shell.qml
//
// Expect a thin top bar with a label + ticking clock. Quit with Ctrl+C.

import QtQuick
import Quickshell

ShellRoot {
    PanelWindow {
        id: bar

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: 36
        color: "#e01e1e2e"

        property string clockText: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: bar.clockText = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: "#7f89b4fa"
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    text: "quickshell prebuilt"
                    color: "#cdd6f4"
                    font.pixelSize: 14
                    font.bold: true
                }

                Text {
                    text: bar.clockText
                    color: "#a6adc8"
                    font.pixelSize: 14
                }
            }
        }
    }
}
