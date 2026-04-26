import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/hierarchy_model.dart';

class HierarchyService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final int maxStations = 32;

  Stream<List<Factory>> getFactories() {
    // On web, Auth token attachment to RTDB can lag right after login.
    // If a screen subscribes immediately, the first read may throw
    // [firebase_database/permission-denied]. We make the stream resilient by
    // retrying on permission-denied (and by forcing a token refresh when possible).
    final controller = StreamController<List<Factory>>.broadcast();

    StreamSubscription<DatabaseEvent>? sub;
    bool closed = false;
    int retry = 0;

    Future<void> start() async {
      if (closed) return;

      // If the app uses Auth, encourage a fresh token before the first RTDB read.
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await user.getIdToken(true);
        } catch (_) {
          // Token refresh failure shouldn't block hierarchy reads.
        }
      }

      sub?.cancel();
      sub = _db.child('hierarchy/factories').onValue.listen(
        (event) {
          retry = 0; // reset on success
          final data = event.snapshot.value;
          if (data == null) {
            controller.add(const <Factory>[]);
            return;
          }
          if (data is! Map) {
            controller.add(const <Factory>[]);
            return;
          }
          final map = Map<Object?, Object?>.from(data);
          final factories = <Factory>[];
          for (var entry in map.entries) {
            try {
              if (entry.value is Map<Object?, Object?>) {
                factories.add(Factory.fromMap(
                    entry.key.toString(), entry.value as Map<Object?, Object?>));
              }
            } catch (e) {
              // Keep stream alive even if one record is malformed.
              // ignore: avoid_print
              print('Error parsing factory ${entry.key}: $e');
            }
          }
          controller.add(factories);
        },
        onError: (Object error, StackTrace stack) async {
          // Only auto-retry on permission-denied; other errors should surface.
          final msg = error.toString().toLowerCase();
          final isPermissionDenied =
              msg.contains('permission-denied') || msg.contains('permission_denied');

          if (!isPermissionDenied) {
            controller.addError(error, stack);
            return;
          }

          retry++;
          final backoffMs = (200 * (1 << (retry - 1))).clamp(200, 4000);
          // ignore: avoid_print
          print('HierarchyService.getFactories retry#$retry in ${backoffMs}ms: $error');

          await Future.delayed(Duration(milliseconds: backoffMs));
          await start();
        },
      );
    }

    // Kick off subscription.
    // ignore: discarded_futures
    start();

    controller.onCancel = () async {
      closed = true;
      await sub?.cancel();
      await controller.close();
    };

    return controller.stream;
  }

  /// Checks if the given factory name, conveyor number, and station number exist in the hierarchy.
  Future<bool> validateLocation(
      String factoryName, int conveyorNumber, int stationNumber) async {
    final factories = await getFactories().first;
    final factory = factories.cast<Factory?>().firstWhere(
          (f) => f?.name == factoryName,
          orElse: () => null,
        );
    if (factory == null) return false;
    final conveyor = factory.conveyors.values.cast<Conveyor?>().firstWhere(
          (c) => c?.number == conveyorNumber,
          orElse: () => null,
        );
    if (conveyor == null) return false;
    final station = conveyor.stations.values.cast<Station?>().firstWhere(
          (s) => s?.id == 'station_$stationNumber',
          orElse: () => null,
        );
    return station != null;
  }

  Future<void> addFactoryWithConveyors(
      String id, String name, String location, int numConveyors) async {
    final factoryRef = _db.child('hierarchy/factories/$id');
    final existing = await factoryRef.get();
    if (existing.exists) {
      throw Exception('Factory with ID "$id" already exists');
    }

    final conveyorsMap = <String, Map<String, dynamic>>{};
    for (int i = 1; i <= numConveyors; i++) {
      final conveyorId = "conveyor_$i";
      conveyorsMap[conveyorId] = {
        'number': i,
        'stations': {}, // empty map, not list
      };
    }

    final factoryMap = {
      'name': name,
      'location': location,
      'conveyors': conveyorsMap,
    };
    await factoryRef.set(factoryMap);
  }

  Future<void> addConveyor(String factoryId, int conveyorNumber) async {
    final conveyorId = "conveyor_$conveyorNumber";
    final conveyorRef =
        _db.child('hierarchy/factories/$factoryId/conveyors/$conveyorId');
    final existing = await conveyorRef.get();
    if (existing.exists) {
      throw Exception(
          'Conveyor $conveyorNumber already exists in this factory');
    }
    final conveyorMap = {
      'number': conveyorNumber,
      'stations': {},
    };
    await conveyorRef.set(conveyorMap);
  }

  Future<void> updateConveyorNumber(
      String factoryId, String conveyorId, int newNumber) async {
    await _db
        .child('hierarchy/factories/$factoryId/conveyors/$conveyorId/number')
        .set(newNumber);
  }

  Future<void> addStation(
      String factoryId, String conveyorId, int stationNumber) async {
    // Use string key to prevent Firebase array conversion
    final stationId = "station_$stationNumber";
    final stationRef = _db.child(
        'hierarchy/factories/$factoryId/conveyors/$conveyorId/stations/$stationId');
    final existing = await stationRef.get();
    if (existing.exists) {
      throw Exception('Station $stationNumber already exists');
    }
    final stationMap = {
      'name': 'Station $stationNumber',
      'address':
          '${factoryId.replaceAll(' ', '_')}_C${conveyorId.replaceAll('conveyor_', '')}_P$stationNumber',
    };
    await stationRef.set(stationMap);
  }

  Future<void> deleteFactory(String factoryId) async {
    await _db.child('hierarchy/factories/$factoryId').remove();
  }

  Future<void> deleteConveyor(String factoryId, String conveyorId) async {
    await _db
        .child('hierarchy/factories/$factoryId/conveyors/$conveyorId')
        .remove();
  }

  Future<int> getActiveAlertsCountForConveyor({
    required String usine,
    required int convoyeur,
  }) async {
    final snapshot = await _db.child('alerts').get();
    final data = snapshot.value;
    if (data == null || data is! Map) {
      return 0;
    }

    int count = 0;
    final alerts = Map<Object?, Object?>.from(data);
    for (final value in alerts.values) {
      if (value is! Map) continue;
      final alert = Map<Object?, Object?>.from(value);
      final status = alert['status']?.toString() ?? '';
      final alertUsine = alert['usine']?.toString() ?? '';
      final alertConvoyeur = int.tryParse('${alert['convoyeur']}');

      final isActive = status == 'disponible' || status == 'en_cours';
      if (isActive && alertUsine == usine && alertConvoyeur == convoyeur) {
        count++;
      }
    }
    return count;
  }
}
