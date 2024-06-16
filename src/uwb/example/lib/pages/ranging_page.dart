import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/subjects.dart';
import 'package:uwb/flutter_uwb.dart';
import 'package:uwb_example/navigator_key.dart';
import 'package:uwb_example/settings.dart';
import 'package:uwb_example/widgets/uwb_listitem.dart';

class RangingPage extends StatefulWidget {
  final Uwb uwbPlugin;
  final String deviceName;

  // Dirty Hack: EventChannel only accepts a single listener

  const RangingPage(
      {super.key, required this.uwbPlugin, required this.deviceName});

  @override
  State<RangingPage> createState() => _RangingPage();
}

class _RangingPage extends State<RangingPage> {
  bool _isUwbSupported = false;

  final BehaviorSubject<Iterable<UwbDevice>> _discoveredDevicesStream =
      BehaviorSubject<Iterable<UwbDevice>>();

  final Map<String, UwbDevice> _devices = {};

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    if (!mounted) return;

    try {
      _isUwbSupported = await widget.uwbPlugin.isUwbSupported();
    } on PlatformException {
      _isUwbSupported = false;
    }

    widget.uwbPlugin.discoveryStateStream.listen((event) {
      switch (event) {
        case DeviceConnectedState(device: var device):
          print(
              "[APP] Device Connected: ${device.name} ${device.id} ${device.state}");
          break;
        case DeviceFoundState(device: var device):
          print(
              "[APP] Device Found: ${device.name} ${device.id} ${device.state}");
          break;
        case DeviceInvitedState(device: var device):
          print(
              "[APP] Device Invited: ${device.name} ${device.id} ${device.state}");
          onDiscoveryDeviceInvited(device);
          break;
        case DeviceInviteRejected(device: var device):
          print("[APP] Device Invited rejected: ${device.id} ${device.state}");
          showErrorDialog("Rejected", "Device rejected.");
          break;
        case DeviceDisconnectedState(device: var device):
          setState(() {
            _devices.remove(device.id);
          });
          print(
              "[APP] Device disconnected: ${device.name} ${device.id} ${device.state}");
        case DeviceLostState(device: var device):
          print("[APP] Device Lost: ${device.id} ${device.state}");
        case _:
          print("[APP] Unknown state");
      }
    });

    widget.uwbPlugin.uwbSessionStateStream.listen(
      (event) {
        switch (event) {
          case UwbSessionStartedState(device: var device):
            print("[APP] Uwb Session Started: ${device.id} ${device.state}");
            setState(() {
              _devices[device.id] = device;
            });
            break;
          case UwbSessionDisconnectedState(device: var device):
            print("[APP] Device Disconnected: ${device.id} ${device.state}");
            setState(() {
              _devices.remove(device.id);
            });
            showErrorDialog("UWB Disconnected",
                "UWB Session disconnected for ${device.name}");
            break;
          case _:
            print("[APP] Unknown state");
        }
      },
    );

    _discoveredDevicesStream
        .addStream(widget.uwbPlugin.discoveredDevicesStream);

    uwbDataStream.asBroadcastStream().listen((devices) {
      setState(() {
        devices.map((e) => {_devices[e.id] = e}).toList();
      });
    });
  }

  @override
  void dispose() async {
    super.dispose();
    await _discoveredDevicesStream.drain();
    _discoveredDevicesStream.close();
  }

  Widget getListCardAction(UwbDevice device) {
    if (device.state == DeviceState.found ||
        device.state == DeviceState.disconnected) {
      return ElevatedButton(
        onPressed: () async {
          try {
            await widget.uwbPlugin.startRanging(device);
          } on PlatformException catch (e) {
            showErrorDialog("Error", "Error: ${e.code} ${e.message}");
          }
        },
        child: const Text(
          "Connect",
        ),
      );
    }

    if (device.state == DeviceState.ranging) {
      return const Text(
        "Ranging",
      );
    }

    if (device.state == DeviceState.connected) {
      return ElevatedButton(
        onPressed: () async {
          try {
            await widget.uwbPlugin.stopRanging(device);
          } on PlatformException catch (e) {
            showErrorDialog("Error", "Error: ${e.code} ${e.message}");
          }
        },
        child: const Text(
          "Stop",
        ),
      );
    }

    if (device.state == DeviceState.pending) {
      return const Text(
        "Pending",
      );
    }

    return const Text(
      "Unknown",
    );
  }

  void onPermissionRequired(PermissionAction action) {
    print("Permission required: $action");
    String actionDescription = "";

    if (action == PermissionAction.request) {
      actionDescription =
          "You need to grant the permission to use UWB for this app.";
    } else {
      actionDescription =
          "You need to grant the permission and restart the app to use UWB.";
    }

    showErrorDialog("Permission Required", actionDescription);
  }

  void showErrorDialog(String title, String description) {
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("Ok"),
          ),
        ],
      ),
    );
  }

  void onDiscoveryDeviceInvited(UwbDevice device) async {
    print("Device invited: ${device.id}");
    bool accepted = false;

    await showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text("Connection Request"),
        content: Text("Do you want to connect to ${device.id}?"),
        actions: [
          TextButton(
            onPressed: () {
              accepted = false;
              Navigator.of(context).pop();
            },
            child: const Text("Decline"),
          ),
          TextButton(
            onPressed: () {
              accepted = true;
              Navigator.of(context).pop();
            },
            child: const Text("Accept"),
          ),
        ],
      ),
    );

    try {
      await widget.uwbPlugin.handleConnectionRequest(device, accepted);
    } on UwbException catch (e) {
      showErrorDialog("Error", "Error: ${e.code} ${e.message}");
    }
  }

  String _getDeviceTypeIcon(UwbDevice device) {
    if (device.deviceType == DeviceType.smartphone) {
      return "📱";
    }
    return "📟";
  }

  void showDiscoveryModal() {
    showModalBottomSheet<void>(
      isScrollControlled: true,
      enableDrag: true,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(40.0),
      ),
      context: context,
      builder: (BuildContext context) {
        return SizedBox(
          height: 400,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                child: const Text(
                  "🔍 Nearby Devices",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  "My Device: ${widget.deviceName}",
                ),
              ),
              StreamBuilder<Iterable<UwbDevice>>(
                stream: _discoveredDevicesStream.stream,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(top: 10),
                        children: snapshot.data!.map(
                          (device) {
                            return Card(
                              color: Colors.white,
                              child: ListTile(
                                title: Text(
                                    "${_getDeviceTypeIcon(device)} ${device.name} (${device.id}) (${device.state})"),
                                trailing: getListCardAction(device),
                              ),
                            );
                          },
                        ).toList(),
                      ),
                    );
                  } else {
                    return const Card(
                      color: Colors.white,
                      child: ListTile(
                        title: Text("No nearby devices found"),
                      ),
                    );
                  }
                },
              ),
              ElevatedButton(
                child: const Text('Close'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Stack(
            alignment: Alignment.centerLeft,
            children: [
              Text(
                "UWB Sessions",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(
            child: Expanded(child: Builder(
              builder: (context) {
                if (_devices.isNotEmpty) {
                  return ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      return UwbListItem(
                        device: _devices.values.toList()[index],
                        uwbPlugin: widget.uwbPlugin,
                      );
                    },
                  );
                }
                return const Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text("No active UWB Sessions"),
                  ),
                );
              },
            )),
          ),
          Container(
            alignment: Alignment.center,
            child: Wrap(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    showDiscoveryModal();
                    try {
                      await widget.uwbPlugin.discoverDevices(widget.deviceName);
                    } on UwbException catch (e) {
                      showErrorDialog("Error", "${e.code} ${e.message}");
                    }
                  },
                  child: const Text('Search'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await widget.uwbPlugin.stopDiscovery();
                  },
                  child: const Text('Stop Search'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
