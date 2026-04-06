// lib/services/repositories/geo_cell_firestore_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/geographic_cell.dart';
import 'firestore_repository_base.dart';

class GeoCellFirestoreRepository extends FirestoreRepositoryBase {
  static const String cellsCollection = 'geographic_cells';

  // B3 FIX: cap for getCellsInWilaya() — cells are small documents but a
  // wilaya can eventually contain hundreds of them. 200 is generous and
  // prevents runaway reads as coverage grows.
  static const int _maxCellsPerWilaya = 200;

  GeoCellFirestoreRepository(super.firestore);

  @override
  String get logTag => '[GeoCellRepo]';

  // --------------------------------------------------------------------------
  // CELLS
  // --------------------------------------------------------------------------

  Future<void> saveCell(GeographicCell cell) async {
    ensureNotDisposed();
    if (cell.id.trim().isEmpty) {
      throw FirestoreServiceException('Cell ID cannot be empty',
          code: 'INVALID_CELL_ID');
    }

    return retryOperation(() async {
      try {
        await firestore
            .collection(cellsCollection)
            .doc(cell.id)
            .set(cell.toMap(), SetOptions(merge: true))
            .timeout(FirestoreRepositoryBase.operationTimeout);
        logInfo('Cell saved: ${cell.id}');
      } catch (e) {
        logError('saveCell', e);
        rethrow;
      }
    });
  }

  Future<GeographicCell?> getCell(String cellId) async {
    ensureNotDisposed();
    if (cellId.trim().isEmpty) {
      logWarning('getCell called with empty cellId');
      return null;
    }

    return retryOperation(() async {
      try {
        final doc = await firestore
            .collection(cellsCollection)
            .doc(cellId)
            .get()
            .timeout(FirestoreRepositoryBase.operationTimeout);
        if (!doc.exists || doc.data() == null) return null;
        return GeographicCell.fromMap(doc.data()!);
      } catch (e) {
        logError('getCell', e);
        return null;
      }
    });
  }

  // B3 FIX: added .limit(_maxCellsPerWilaya) to prevent an unbounded read
  // as the number of cells per wilaya grows in production.
  Future<List<GeographicCell>> getCellsInWilaya(int wilayaCode) async {
    ensureNotDisposed();
    return retryOperation(() async {
      try {
        final snapshot = await firestore
            .collection(cellsCollection)
            .where('wilayaCode', isEqualTo: wilayaCode)
            .limit(_maxCellsPerWilaya)
            .get()
            .timeout(FirestoreRepositoryBase.operationTimeout);
        return snapshot.docs
            .map((doc) {
              try {
                return GeographicCell.fromMap(doc.data());
              } catch (e) {
                logError('getCellsInWilaya.parsing', e);
                return null;
              }
            })
            .whereType<GeographicCell>()
            .toList();
      } catch (e) {
        logError('getCellsInWilaya', e);
        return [];
      }
    });
  }

  // --------------------------------------------------------------------------
  // DISPOSE
  // --------------------------------------------------------------------------

  void dispose() {
    if (isDisposed) return;
    markDisposed();
    logInfo('GeoCellFirestoreRepository disposed');
  }
}
