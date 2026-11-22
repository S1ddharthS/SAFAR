import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:safar_mobile/core/ai/image_feature_extractor.dart';
import 'package:safar_mobile/core/models/expenses.dart';
import 'package:safar_mobile/core/models/memories.dart';
import 'package:safar_mobile/core/native/file_exporter.dart';
import 'package:safar_mobile/core/services/ocr_service.dart';
import 'package:safar_mobile/core/services/voice_recorder_service.dart';
import 'package:safar_mobile/features/trip/pdf_travel_book_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F18 — Premium Travel Book PDF Generator', () {
    test('generates valid multi-page PDF document starting with %PDF- signature', () async {
      final replay = ReplayResponse(
        trip: const ReplayTrip(
          id: 'trip-kyoto-42',
          name: 'Autumn in Kyoto',
          destination: 'Kyoto, Japan',
          startDate: '2026-10-10',
          endDate: '2026-10-17',
        ),
        stats: const ReplayStats(
          daysRecorded: 7,
          memories: 14,
          media: 12,
          approvedEvents: 3,
          contributors: 2,
        ),
        permissions: 'contributor',
        formatNote: 'Confidential journey archive',
        days: const [
          ReplayDay(
            date: '2026-10-10',
            items: [
              ReplayItem(
                id: 'item-1',
                title: 'Check-in at Ryokan Gion',
                startTime: '14:00',
                protected: false,
              ),
              ReplayItem(
                id: 'item-2',
                title: 'Evening walk along Shirakawa Canal',
                startTime: '18:30',
                protected: false,
              ),
            ],
            memories: [
              Memory(
                id: 'mem-1',
                userId: 'user-1',
                kind: 'photo',
                capturedAt: '2026-10-10T19:00:00Z',
                visibility: 'trip',
                aiGenerated: false,
                approved: true,
                caption: 'Golden lantern glow reflecting across the cobblestones.',
                mediaUrl: '/media/kyoto_gion.jpg',
              ),
              Memory(
                id: 'mem-2',
                userId: 'user-2',
                kind: 'text',
                capturedAt: '2026-10-10T21:15:00Z',
                visibility: 'trip',
                aiGenerated: false,
                approved: true,
                textContent: 'The quiet evening stillness here is unlike anything else.',
              ),
            ],
            events: [
              ReplayEvent(
                id: 'evt-1',
                title: 'Gion Canal Twilight',
                summary: 'Evening exploration of historical preserved alleys',
                memoryIds: ['mem-1', 'mem-2'],
              ),
            ],
          ),
          ReplayDay(
            date: '2026-10-11',
            items: [
              ReplayItem(
                id: 'item-3',
                title: 'Fushimi Inari Taisha early morning ascent',
                startTime: '06:30',
                protected: false,
              ),
            ],
            memories: [
              Memory(
                id: 'mem-3',
                userId: 'user-1',
                kind: 'voice',
                capturedAt: '2026-10-11T07:15:00Z',
                visibility: 'trip',
                aiGenerated: false,
                approved: true,
                caption: 'Listening to the morning breeze through thousands of vermilion torii gates.',
                mediaUrl: '/media/inari_breeze.wav',
              ),
            ],
            events: [],
          ),
        ],
      );

      const expenses = ExpenseTotals(
        items: [
          Expense(
            id: 'exp-1',
            title: 'Ryokan Gion Lodging',
            category: 'lodging',
            amount: 70000,
            currency: 'JPY',
            paidBy: 'user-1',
            incurredOn: '2026-10-10',
          ),
          Expense(
            id: 'exp-2',
            title: 'Traditional Kaiseki Dinner',
            category: 'dining',
            amount: 45000,
            currency: 'JPY',
            paidBy: 'user-2',
            incurredOn: '2026-10-10',
          ),
        ],
        totals: {'lodging': 70000, 'dining': 45000},
      );

      final pdfBytes = await PdfTravelBookGenerator.generate(
        replay: replay,
        expenseTotals: expenses,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1500));

      // Validate standard PDF magic bytes "%PDF-"
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));

      // Validate PDF ends with EOF marker
      final tail = String.fromCharCodes(pdfBytes.sublist(pdfBytes.length - 12));
      expect(tail.contains('%%EOF'), isTrue);
    });

    test('generates clean PDF even when expenses and daily items are sparse/empty', () async {
      final minimalReplay = ReplayResponse(
        trip: const ReplayTrip(
          id: 'trip-sparse-1',
          name: 'Solo Retreat',
          destination: 'Mount Hiei',
          startDate: '2026-11-01',
          endDate: '2026-11-03',
        ),
        stats: const ReplayStats(
          daysRecorded: 0,
          memories: 0,
          media: 0,
          approvedEvents: 0,
          contributors: 1,
        ),
        permissions: 'owner',
        formatNote: 'Draft replay',
        days: const [],
      );

      final pdfBytes = await PdfTravelBookGenerator.generate(
        replay: minimalReplay,
        expenseTotals: null,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(800));
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('FileExporter.saveBytesToCache writes binary PDF file correctly', () async {
      final tempDir = Directory.systemTemp.createTempSync('safar_pdf_test_');
      try {
        final exporter = FileExporter();
        final dummyBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35]); // %PDF-1.5

        final result = await exporter.saveBytesToCache(
          filename: 'travel_book_kyoto.pdf',
          bytes: dummyBytes,
          mimeType: 'application/pdf',
          customDirectory: tempDir,
        );

        expect(result.file.existsSync(), isTrue);
        expect(result.filename, equals('travel_book_kyoto.pdf'));
        expect(result.mimeType, equals('application/pdf'));
        expect(result.bytesCount, equals(8));
        expect(result.file.readAsBytesSync(), equals(dummyBytes));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('F17 — Dream Import OCR Service', () {
    test('OcrResult preserves text, blocks, lines and error states', () {
      const result = OcrResult(
        text: 'Flight NH801\nDeparture 10:45 AM\nGate 42',
        blocksCount: 3,
        linesCount: 3,
      );

      expect(result.hasText, isTrue);
      expect(result.blocksCount, equals(3));
      expect(result.linesCount, equals(3));
      expect(result.error, isNull);

      const emptyResult = OcrResult(
        text: '',
        blocksCount: 0,
        linesCount: 0,
      );
      expect(emptyResult.hasText, isFalse);
      expect(emptyResult.text, isEmpty);

      const errorResult = OcrResult(
        text: '',
        blocksCount: 0,
        linesCount: 0,
        error: 'Image unreadable or corrupt',
      );
      expect(errorResult.hasText, isFalse);
      expect(errorResult.error, equals('Image unreadable or corrupt'));
    });
  });

  group('F11 — Shared Memories: Voice, Video & Upload Reliability', () {
    test('RecordingStatus and AudioPlaybackStatus enum definitions', () {
      expect(RecordingStatus.values, contains(RecordingStatus.idle));
      expect(RecordingStatus.values, contains(RecordingStatus.recording));
      expect(RecordingStatus.values, contains(RecordingStatus.paused));
      expect(RecordingStatus.values, contains(RecordingStatus.stopped));

      expect(AudioPlaybackStatus.values, contains(AudioPlaybackStatus.stopped));
      expect(AudioPlaybackStatus.values, contains(AudioPlaybackStatus.playing));
      expect(AudioPlaybackStatus.values, contains(AudioPlaybackStatus.paused));
    });

    test('CancelToken successfully halts Dio upload operation', () async {
      final cancelToken = CancelToken();
      expect(cancelToken.isCancelled, isFalse);

      cancelToken.cancel('Upload cancelled by user');
      expect(cancelToken.isCancelled, isTrue);
      expect(cancelToken.cancelError?.error, equals('Upload cancelled by user'));
    });
  });

  group('F12 — Memory Studio On-Device Image Feature Extractor', () {
    test('extracts 128-dimensional unit feature vector from image bytes', () {
      const extractor = ImageFeatureExtractor();

      // Create a synthetic 32x32 test RGB image
      final testImage = img.Image(width: 32, height: 32);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          testImage.setPixelRgb(x, y, x * 7, y * 7, (x + y) * 3);
        }
      }
      final encodedPng = Uint8List.fromList(img.encodePng(testImage));

      final embedding = extractor.extract(encodedPng);
      expect(embedding, isNotNull);
      expect(embedding!.dimension, equals(128));
      expect(embedding.vector.length, equals(128));

      // Verify L2 unit normalization: sqrt(sum(v^2)) ≈ 1.0
      double sumSq = 0.0;
      for (final v in embedding.vector) {
        sumSq += v * v;
      }
      final l2Norm = math.sqrt(sumSq);
      expect(l2Norm, closeTo(1.0, 0.01));
    });

    test('cosine similarity is 1.0 for identical image embeddings', () {
      final vecA = List<double>.generate(128, (i) => math.sin(i.toDouble()));
      double sumSq = 0.0;
      for (final v in vecA) {
        sumSq += v * v;
      }
      final norm = math.sqrt(sumSq);
      final normalized = vecA.map((v) => v / norm).toList();

      final embA = ImageEmbedding(vector: normalized, dimension: 128);
      final embB = ImageEmbedding(vector: List<double>.from(normalized), dimension: 128);

      final similarity = embA.cosineSimilarity(embB);
      expect(similarity, closeTo(1.0, 0.0001));
    });

    test('cosine similarity distinguishes distinct scene embeddings', () {
      const extractor = ImageFeatureExtractor();

      // Image A: Warm sunset gradient (High Red, Low Blue)
      final imageA = img.Image(width: 32, height: 32);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          imageA.setPixelRgb(x, y, 240, 90, 20);
        }
      }
      final bytesA = Uint8List.fromList(img.encodePng(imageA));

      // Image B: Cool night scene (Low Red, High Blue)
      final imageB = img.Image(width: 32, height: 32);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          imageB.setPixelRgb(x, y, 10, 30, 220);
        }
      }
      final bytesB = Uint8List.fromList(img.encodePng(imageB));

      final embA = extractor.extract(bytesA)!;
      final embB = extractor.extract(bytesB)!;

      final similarity = embA.cosineSimilarity(embB);
      expect(similarity, lessThan(0.85));
      expect(similarity, greaterThanOrEqualTo(0.0));
    });
  });
}
