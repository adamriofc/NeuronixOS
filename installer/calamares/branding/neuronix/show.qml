import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: presentation
    color: "#16161e"
    anchors.fill: parent

    property int currentSlide: 0
    property int totalSlides: 5

    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: {
            currentSlide = (currentSlide + 1) % totalSlides
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 30

        // Slide 1: Substrate
        Item {
            anchors.fill: parent
            visible: currentSlide === 0
            opacity: currentSlide === 0 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16
                width: parent.width * 0.85

                Text {
                    text: "NEURONIX OS"
                    color: "#7aa2f7"
                    font.pixelSize: 26
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Provable Adaptive Systems Substrate"
                    color: "#bb9af7"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Built on declarative NixOS with pinned flake reproducibility, immutable system store, and mathematically verifiable generational lifecycles."
                    color: "#a9b1d6"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }
        }

        // Slide 2: Conductor
        Item {
            anchors.fill: parent
            visible: currentSlide === 1
            opacity: currentSlide === 1 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16
                width: parent.width * 0.85

                Text {
                    text: "Conductor Control Center"
                    color: "#7aa2f7"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Quiet Systems UI with Ghostty and GNOME Wayland Tokyo Aesthetics"
                    color: "#7dcfff"
                    font.pixelSize: 15
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Real-time hardware telemetry, non-blocking asynchronous operations, pure-text design, and one-click atomic upgrades and rollbacks without desktop interruption."
                    color: "#a9b1d6"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }
        }

        // Slide 3: Hyperion
        Item {
            anchors.fill: parent
            visible: currentSlide === 2
            opacity: currentSlide === 2 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16
                width: parent.width * 0.85

                Text {
                    text: "Project Hyperion"
                    color: "#7aa2f7"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Provable Adaptive Execution Architecture (PAEA)"
                    color: "#e0af68"
                    font.pixelSize: 15
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Four deterministic execution tiers ranging from native host execution to volatile RAM ghosts, eBPF LSM enclaves, and micro-VM isolation backed by cryptographic Merkle receipts."
                    color: "#a9b1d6"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }
        }

        // Slide 4: Storage & Rollback
        Item {
            anchors.fill: parent
            visible: currentSlide === 3
            opacity: currentSlide === 3 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16
                width: parent.width * 0.85

                Text {
                    text: "Resilient Storage & Atomic Rollback"
                    color: "#7aa2f7"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Btrfs Subvolumes with 7-Factor Safety Firewall"
                    color: "#9ece6a"
                    font.pixelSize: 15
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Five dedicated subvolumes (@, @nix, @home, @snapshots, @swap) with ZSTD compression, daily auto-TRIM, and sub-millisecond atomic state rollback."
                    color: "#a9b1d6"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }
        }

        // Slide 5: Developer Stacks
        Item {
            anchors.fill: parent
            visible: currentSlide === 4
            opacity: currentSlide === 4 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16
                width: parent.width * 0.85

                Text {
                    text: "Hermetic Developer Stacks"
                    color: "#7aa2f7"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Zero-Setup Isolated Toolchains & Built-in AI Copilot"
                    color: "#f7768e"
                    font.pixelSize: 15
                    font.bold: true
                    font.family: "Sans"
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Instant declarative environments for Python (uv), Rust (cargo), Node.js (pnpm), and PyTorch, complete with autonomous local AI assistance."
                    color: "#a9b1d6"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }
        }

        // Slide Indicators
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: totalSlides
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: index === currentSlide ? "#7aa2f7" : "#3b4261"
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }
        }
    }
}
