import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/models/common.dart';
import 'package:safar_mobile/core/models/expenses.dart';
import 'package:safar_mobile/core/models/memories.dart';
import 'package:safar_mobile/core/models/trip.dart';
import 'package:safar_mobile/core/native/file_exporter.dart';
import 'package:safar_mobile/core/network/api_client.dart';
import 'package:safar_mobile/core/network/api_exception.dart';
import 'package:safar_mobile/core/network/cookie_jar.dart';
import 'package:safar_mobile/core/providers.dart';
import 'package:safar_mobile/core/repositories/expense_repository.dart';
import 'package:safar_mobile/core/repositories/memory_repository.dart';
import 'package:safar_mobile/core/repositories/trip_repository.dart';
import 'package:safar_mobile/core/repositories/user_repository.dart';
import 'package:safar_mobile/core/storage/json_store.dart';
import 'package:safar_mobile/core/theme/safar_theme.dart';
import 'package:safar_mobile/features/profile/settings_screen.dart';
import 'package:safar_mobile/features/trip/expenses_screen.dart';
import 'package:safar_mobile/features/trip/replay_screen.dart';

class _FakeFileExporter extends FileExporter {
  _FakeFileExporter(this.tempDir);

  final Directory tempDir;
  File? lastOpenedFile;
  File? lastSharedFile;
  String? lastSharedMimeType;
  String? lastSharedTitle;
  int openCallCount = 0;
  int shareCallCount = 0;

  @override
  Future<ExportedFileResult> saveToCache({
    required String filename,
    required String content,
    required String mimeType,
    Directory? customDirectory,
  }) async {
    final sanitized = FileExporter.sanitizeFilename(filename);
    final file = File('${tempDir.path}/$sanitized');
    file.writeAsStringSync(content);
    return ExportedFileResult(
      file: file,
      filename: sanitized,
      mimeType: mimeType,
      bytesCount: file.lengthSync(),
      content: content,
    );
  }

  @override
  Future<bool> openFile(File file) async {
    openCallCount++;
    lastOpenedFile = file;
    return true;
  }

  @override
  Future<bool> shareFile({
    required File file,
    required String mimeType,
    required String title,
    String? subject,
    String? text,
  }) async {
    shareCallCount++;
    lastSharedFile = file;
    lastSharedMimeType = mimeType;
    lastSharedTitle = title;
    return true;
  }
}

class _MockMemoryRepo extends MemoryRepository {
  _MockMemoryRepo(super.api);

  ReplayResponse? replayData;
  String mockTravelBookResult = '<!DOCTYPE html><html><body><h1>Kyoto Replay</h1></body></html>';
  bool throwError = false;

  @override
  Future<ReplayResponse> replay(String tripId) async => replayData!;

  @override
  Future<String> travelBook(String tripId) async {
    if (throwError) {
      throw ApiException(message: 'Failed to generate travel book on server', statusCode: 500);
    }
    return mockTravelBookResult;
  }
}

class _MockExpenseRepo extends ExpenseRepository {
  _MockExpenseRepo(super.api);

  String mockCsvResult = 'date,title,payer,amount,currency,split_type,members\n2026-11-20,Matcha Ice Cream,Mira,8.50,EUR,equal,3';
  bool throwError = false;

  @override
  Future<ExpenseTotals> list(String tripId) async => const ExpenseTotals(items: [], totals: {});

  @override
  Future<BalancesResponse> balances(String tripId) async => const BalancesResponse(
    balances: [],
    settlements: [],
    totalSpent: 0,
    currency: 'EUR',
    disclosure: 'Shared expenses visible.',
  );

  @override
  Future<String> exportCsv(String tripId) async {
    if (throwError) {
      throw ApiException(message: 'Expenses export unauthorized or failed', statusCode: 403);
    }
    return mockCsvResult;
  }
}

class _MockUserRepo extends UserRepository {
  _MockUserRepo(super.api);

  Me? meData;
  String mockExportData = '{"profile":{"displayName":"Mira","email":"mira@safar.demo"},"consents":{"personalization":true}}';
  bool throwError = false;

  @override
  Future<Me> me() async => meData!;

  @override
  Future<String> exportData() async {
    if (throwError) {
      throw ApiException(message: 'User data export failed: session expired', statusCode: 401);
    }
    return mockExportData;
  }
}

class _MockTripRepo extends TripRepository {
  _MockTripRepo(super.api);

  Trip? tripData;

  @override
  Future<Trip> get(String tripId) async => tripData!;

  @override
  Future<List<Member>> members(String tripId) async => const [];
}

ApiClient _createApiClient() {
  final store = MemoryJsonStore();
  return ApiClient(baseUrl: 'http://localhost:8000', jar: SafarCookieJar(store), store: store);
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: SafarTheme.light(),
      home: child,
    ),
  );
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late _FakeFileExporter fakeExporter;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('safar_export_test_');
    fakeExporter = _FakeFileExporter(tempDir);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('FileExporter Core Utility Tests', () {
    test('saveToCache creates physical file with correct content and extension', () async {
      const htmlContent = '<!DOCTYPE html><html><head><title>Test</title></head><body><h1>Hello</h1></body></html>';
      final result = await fakeExporter.saveToCache(
        filename: 'travel_book_kyoto.html',
        content: htmlContent,
        mimeType: 'text/html',
      );

      expect(result.file.existsSync(), isTrue);
      expect(result.filename, equals('travel_book_kyoto.html'));
      expect(result.mimeType, equals('text/html'));
      expect(result.bytesCount, equals(htmlContent.length));
      expect(result.formattedSize, contains('B'));
      expect(result.file.readAsStringSync(), equals(htmlContent));
    });

    test('sanitizeFilename removes path traversal and special characters', () {
      expect(FileExporter.sanitizeFilename('../../etc/passwd.json'), equals('etc_passwd.json'));
      expect(FileExporter.sanitizeFilename('Kyoto / Autumn & Wander?.html'), equals('Kyoto_Autumn_Wander.html'));
      expect(FileExporter.sanitizeFilename(''), equals('export'));
    });

    test('shareFile and openFile invoke platform delegate correctly', () async {
      final file = File('${tempDir.path}/test.csv');
      file.writeAsStringSync('col1,col2\nval1,val2');

      final opened = await fakeExporter.openFile(file);
      expect(opened, isTrue);
      expect(fakeExporter.openCallCount, equals(1));
      expect(fakeExporter.lastOpenedFile?.path, equals(file.path));

      final shared = await fakeExporter.shareFile(
        file: file,
        mimeType: 'text/csv',
        title: 'Share CSV',
      );
      expect(shared, isTrue);
      expect(fakeExporter.shareCallCount, equals(1));
      expect(fakeExporter.lastSharedFile?.path, equals(file.path));
      expect(fakeExporter.lastSharedMimeType, equals('text/csv'));
    });
  });

  group('ExportActionSheet Widget Tests', () {
    testWidgets('renders file information, "Saved" status badge, and action buttons', (tester) async {
      final file = File('${tempDir.path}/export_demo.json');
      file.writeAsStringSync('{"key":"value"}');

      final result = ExportedFileResult(
        file: file,
        filename: 'export_demo.json',
        mimeType: 'application/json',
        bytesCount: 15,
        content: '{"key":"value"}',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SafarTheme.light(),
          home: Scaffold(
            body: ExportActionSheet(
              result: result,
              title: 'Personal data archive ready',
              subtitle: 'A full export of your profile.',
              formatLabel: 'JSON Archive',
              formatIcon: Icons.data_object_outlined,
              openActionLabel: 'Open archive',
              shareActionLabel: 'Share archive',
              infoBannerText: 'Private member information excluded.',
              fileExporter: fakeExporter,
            ),
          ),
        ),
      );

      expect(find.text('Personal data archive ready'), findsOneWidget);
      expect(find.text('export_demo.json'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Open archive'), findsOneWidget);
      expect(find.text('Share archive'), findsOneWidget);
      expect(find.text('Private member information excluded.'), findsOneWidget);

      // Tap share
      await tester.tap(find.text('Share archive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeExporter.shareCallCount, equals(1));

      // Tap open
      await tester.tap(find.text('Open archive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeExporter.openCallCount, equals(1));
    });
  });

  group('F18 Travel Book Integration in ReplayScreen', () {
    testWidgets('Open travel book saves HTML and presents ExportActionSheet instead of raw HTML', (tester) async {
      _usePhoneViewport(tester);
      final apiClient = _createApiClient();
      final mockMemory = _MockMemoryRepo(apiClient);

      const replayTrip = ReplayTrip(
        id: 'trip-kyoto',
        name: 'Kyoto in Slow Bloom',
        destination: 'Kyoto, Japan',
        startDate: '2026-11-20',
        endDate: '2026-11-25',
      );

      final replayData = ReplayResponse(
        trip: replayTrip,
        stats: const ReplayStats(daysRecorded: 5, memories: 12, approvedEvents: 4, media: 8, contributors: 4),
        days: const [],
        permissions: 'Private memories excluded.',
        formatNote: 'Print-ready HTML document.',
      );
      mockMemory.replayData = replayData;

      await tester.pumpWidget(
        _wrap(
          const ReplayScreen(tripId: 'trip-kyoto'),
          [
            memoryRepositoryProvider.overrideWithValue(mockMemory),
            replayProvider('trip-kyoto').overrideWith((ref) async => replayData),
            fileExporterProvider.overrideWithValue(fakeExporter),
          ],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Export HTML Travel Book'), findsOneWidget);
      await tester.tap(find.text('Export HTML Travel Book'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Asserts ExportActionSheet is mounted with proper details
      expect(find.text('Travel book ready'), findsOneWidget);
      expect(find.text('View in browser'), findsOneWidget);
      expect(find.text('Share document'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);

      // Asserts that raw HTML string is NEVER displayed in SelectableText
      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('<!DOCTYPE html>'), findsNothing);

      // Verify the generated file in cache contains the exact HTML content
      final exportedFiles = tempDir.listSync().whereType<File>().toList();
      expect(exportedFiles.isNotEmpty, isTrue);
      final bookFile = exportedFiles.firstWhere((f) => f.path.endsWith('.html'));
      expect(bookFile.readAsStringSync(), equals(mockMemory.mockTravelBookResult));
    });

    testWidgets('Empty travel book returns helpful message and does not crash', (tester) async {
      _usePhoneViewport(tester);
      final apiClient = _createApiClient();
      final mockMemory = _MockMemoryRepo(apiClient);
      mockMemory.mockTravelBookResult = '   '; // empty/whitespace

      const replayTrip = ReplayTrip(
        id: 'trip-kyoto',
        name: 'Kyoto in Slow Bloom',
        destination: 'Kyoto, Japan',
        startDate: '2026-11-20',
        endDate: '2026-11-25',
      );

      final replayData = ReplayResponse(
        trip: replayTrip,
        stats: const ReplayStats(daysRecorded: 0, memories: 0, approvedEvents: 0, media: 0, contributors: 1),
        days: const [],
        permissions: 'Private memories excluded.',
        formatNote: 'Print-ready HTML document.',
      );
      mockMemory.replayData = replayData;

      await tester.pumpWidget(
        _wrap(
          const ReplayScreen(tripId: 'trip-kyoto'),
          [
            memoryRepositoryProvider.overrideWithValue(mockMemory),
            replayProvider('trip-kyoto').overrideWith((ref) async => replayData),
            fileExporterProvider.overrideWithValue(fakeExporter),
          ],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Export HTML Travel Book'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No recorded memories or days found to export.'), findsOneWidget);
      expect(find.text('Travel book ready'), findsNothing);
    });

    testWidgets('Travel book API error shows snackbar with failure detail', (tester) async {
      _usePhoneViewport(tester);
      final apiClient = _createApiClient();
      final mockMemory = _MockMemoryRepo(apiClient);
      mockMemory.throwError = true;

      const replayTrip = ReplayTrip(
        id: 'trip-kyoto',
        name: 'Kyoto',
        destination: 'Kyoto, Japan',
        startDate: '2026-11-20',
        endDate: '2026-11-25',
      );

      final replayData = ReplayResponse(
        trip: replayTrip,
        stats: const ReplayStats(daysRecorded: 1, memories: 1, approvedEvents: 1, media: 1, contributors: 1),
        days: const [],
        permissions: 'Private memories excluded.',
        formatNote: 'Print-ready HTML document.',
      );
      mockMemory.replayData = replayData;

      await tester.pumpWidget(
        _wrap(
          const ReplayScreen(tripId: 'trip-kyoto'),
          [
            memoryRepositoryProvider.overrideWithValue(mockMemory),
            replayProvider('trip-kyoto').overrideWith((ref) async => replayData),
            fileExporterProvider.overrideWithValue(fakeExporter),
          ],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Export HTML Travel Book'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Failed to generate travel book on server'), findsOneWidget);
    });
  });

  group('F13 Group Expenses CSV Export in ExpensesScreen', () {
    testWidgets('Export CSV saves .csv file and presents ExportActionSheet instead of raw text', (tester) async {
      _usePhoneViewport(tester);
      final apiClient = _createApiClient();
      final mockExpense = _MockExpenseRepo(apiClient);
      final mockTrip = _MockTripRepo(apiClient);

      const trip = Trip(
        id: 'trip-kyoto',
        name: 'Kyoto in Slow Bloom',
        destinationName: 'Kyoto, Japan',
        startDate: '2026-11-20',
        endDate: '2026-11-25',
        groupSize: 3,
        currency: 'EUR',
        baseLat: 35.0,
        baseLon: 135.0,
        status: 'active',
        privacy: 'private',
        createdBy: 'u-mira',
        memberCount: 3,
        myRole: 'owner',
      );
      mockTrip.tripData = trip;

      await tester.pumpWidget(
        _wrap(
          const ExpensesScreen(tripId: 'trip-kyoto'),
          [
            tripRepositoryProvider.overrideWithValue(mockTrip),
            tripProvider('trip-kyoto').overrideWith((ref) async => trip),
            expenseRepositoryProvider.overrideWithValue(mockExpense),
            expensesProvider('trip-kyoto').overrideWith((ref) async => const ExpenseTotals(items: [], totals: {})),
            balancesProvider('trip-kyoto').overrideWith((ref) async => const BalancesResponse(
              balances: [],
              settlements: [],
              totalSpent: 0,
              currency: 'EUR',
              disclosure: 'Shared expenses visible.',
            )),
            membersProvider('trip-kyoto').overrideWith((ref) async => const []),
            fileExporterProvider.overrideWithValue(fakeExporter),
          ],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byTooltip('Export CSV'), findsOneWidget);
      await tester.tap(find.byTooltip('Export CSV'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Asserts ExportActionSheet is displayed
      expect(find.text('Expenses CSV ready'), findsOneWidget);
      expect(find.text('Share CSV'), findsOneWidget);
      expect(find.text('Open in app'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);

      // Asserts raw CSV text is NOT displayed in SelectableText
      expect(find.byType(SelectableText), findsNothing);

      // Verify the saved CSV file on disk matches backend payload exactly
      final exportedFiles = tempDir.listSync().whereType<File>().toList();
      final csvFile = exportedFiles.firstWhere((f) => f.path.endsWith('.csv'));
      expect(csvFile.readAsStringSync(), equals(mockExpense.mockCsvResult));
    });
  });

  group('F01 Personal Data Export in SettingsScreen', () {
    testWidgets('Export my data saves .json file and presents ExportActionSheet instead of raw JSON', (tester) async {
      _usePhoneViewport(tester);
      final apiClient = _createApiClient();
      final mockUser = _MockUserRepo(apiClient);

      const me = Me(
        user: User(id: 'u-mira', email: 'mira@safar.demo', displayName: 'Mira Okafor', isAdmin: false),
        profile: Profile(locationSharing: false),
        dna: Dna(),
        consents: {},
        policyVersion: '2026-01',
      );
      mockUser.meData = me;

      await tester.pumpWidget(
        _wrap(
          const SettingsScreen(),
          [
            userRepositoryProvider.overrideWithValue(mockUser),
            meProvider.overrideWith((ref) async => me),
            fileExporterProvider.overrideWithValue(fakeExporter),
          ],
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final exportFinder = find.text('Export my data');
      await tester.scrollUntilVisible(exportFinder, 200);
      expect(exportFinder, findsOneWidget);
      await tester.tap(exportFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Asserts ExportActionSheet is displayed
      expect(find.text('Personal data archive ready'), findsOneWidget);
      expect(find.text('Share archive'), findsOneWidget);
      expect(find.text('Open archive'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);

      // Asserts raw JSON is NOT displayed in SelectableText
      expect(find.byType(SelectableText), findsNothing);

      // Verify the saved JSON file on disk matches backend payload exactly
      final exportedFiles = tempDir.listSync().whereType<File>().toList();
      final jsonFile = exportedFiles.firstWhere((f) => f.path.endsWith('.json'));
      expect(jsonFile.readAsStringSync(), equals(mockUser.mockExportData));
    });
  });
}
