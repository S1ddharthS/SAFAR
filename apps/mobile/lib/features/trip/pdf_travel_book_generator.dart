import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/expenses.dart';
import '../../core/models/memories.dart';
import '../../core/utils/format.dart';

/// Editorial styling constants for the SAFAR Travel Book PDF.
class TravelBookTheme {
  static const ivory = PdfColor.fromInt(0xFFFAF8F5);
  static const charcoal = PdfColor.fromInt(0xFF1F2124);
  static const slate = PdfColor.fromInt(0xFF4A4E54);
  static const muted = PdfColor.fromInt(0xFF767B82);
  static const ember = PdfColor.fromInt(0xFFA45A2A);
  static const sand = PdfColor.fromInt(0xFFC49A45);
  static const jade = PdfColor.fromInt(0xFF2D5A46);
  static const line = PdfColor.fromInt(0xFFE2DDD5);
  static const cardBg = PdfColor.fromInt(0xFFF3EFEA);
}

/// Generates a genuine, beautifully designed editorial PDF Travel Book.
class PdfTravelBookGenerator {
  const PdfTravelBookGenerator();

  /// Generates the complete PDF document as bytes.
  static Future<Uint8List> generate({
    required ReplayResponse replay,
    ExpenseTotals? expenseTotals,
    BalancesResponse? balances,
  }) async {
    final pdf = pw.Document(
      title: 'SAFAR Travel Book — ${replay.trip.name}',
      author: 'SAFAR Living Journey Network',
      subject: 'A preserved record of ${replay.trip.name} in ${replay.trip.destination}',
      keywords: 'travel book, safar, memoir, ${replay.trip.destination}',
    );

    // Try loading the custom serif font (Lora). Fall back cleanly to Helvetica/Times.
    pw.Font? serifFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/Lora-Variable.ttf');
      serifFont = pw.Font.ttf(fontData);
    } catch (_) {
      serifFont = null;
    }

    final displayFont = serifFont ?? pw.Font.timesBold();
    final bodyFont = pw.Font.helvetica();
    final bodyBoldFont = pw.Font.helveticaBold();
    final bodyObliqueFont = pw.Font.helveticaOblique();

    // 1. Cover Page
    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(48),
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: TravelBookTheme.ivory),
          ),
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'SAFAR  ·  THE LIVING JOURNEY NETWORK',
                  style: pw.TextStyle(
                    font: bodyBoldFont,
                    fontSize: 8.5,
                    letterSpacing: 2.0,
                    color: TravelBookTheme.ember,
                  ),
                ),
                pw.Text(
                  'EDITORIAL EDITION',
                  style: pw.TextStyle(
                    font: bodyFont,
                    fontSize: 8.5,
                    letterSpacing: 1.5,
                    color: TravelBookTheme.muted,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Container(height: 1, color: TravelBookTheme.line),
            pw.Spacer(flex: 2),

            // Kicker
            pw.Text(
              'A JOURNEY MEMOIR',
              style: pw.TextStyle(
                font: bodyBoldFont,
                fontSize: 10,
                letterSpacing: 3.0,
                color: TravelBookTheme.sand,
              ),
            ),
            pw.SizedBox(height: 14),

            // Title
            pw.Text(
              replay.trip.name,
              style: pw.TextStyle(
                font: displayFont,
                fontSize: 34,
                color: TravelBookTheme.charcoal,
                lineSpacing: 1.2,
              ),
            ),
            pw.SizedBox(height: 10),

            // Destination & Dates
            pw.Text(
              replay.trip.destination,
              style: pw.TextStyle(
                font: displayFont,
                fontSize: 18,
                color: TravelBookTheme.ember,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '${formatDate(replay.trip.startDate)}  —  ${formatDate(replay.trip.endDate)}',
              style: pw.TextStyle(
                font: bodyFont,
                fontSize: 11,
                color: TravelBookTheme.slate,
                letterSpacing: 0.5,
              ),
            ),

            pw.SizedBox(height: 24),
            pw.Container(
              width: 60,
              height: 2,
              color: TravelBookTheme.ember,
            ),
            pw.Spacer(flex: 3),

            // Cover Capsule Stats
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: pw.BoxDecoration(
                color: TravelBookTheme.cardBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: TravelBookTheme.line, width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _statItem('RECORDED DAYS', '${replay.stats.daysRecorded}', bodyFont, bodyBoldFont),
                  _dividerVertical(),
                  _statItem('SHARED MOMENTS', '${replay.stats.memories}', bodyFont, bodyBoldFont),
                  _dividerVertical(),
                  _statItem('APPROVED STORIES', '${replay.stats.approvedEvents}', bodyFont, bodyBoldFont),
                  _dividerVertical(),
                  _statItem('CONTRIBUTORS', '${replay.stats.contributors}', bodyFont, bodyBoldFont),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Colophon Footnote
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Preserved with privacy-first member permissions',
                  style: pw.TextStyle(
                    font: bodyObliqueFont,
                    fontSize: 8,
                    color: TravelBookTheme.muted,
                  ),
                ),
                pw.Text(
                  'safartravel.network',
                  style: pw.TextStyle(
                    font: bodyFont,
                    fontSize: 8,
                    color: TravelBookTheme.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // 2. MultiPage Chapter & Days
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 44),
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: TravelBookTheme.ivory),
          ),
        ),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 16),
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: TravelBookTheme.line, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                replay.trip.name.toUpperCase(),
                style: pw.TextStyle(
                  font: bodyBoldFont,
                  fontSize: 7.5,
                  letterSpacing: 1.2,
                  color: TravelBookTheme.muted,
                ),
              ),
              pw.Text(
                'SAFAR TRAVEL BOOK',
                style: pw.TextStyle(
                  font: bodyFont,
                  fontSize: 7.5,
                  letterSpacing: 1.2,
                  color: TravelBookTheme.muted,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 16),
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: TravelBookTheme.line, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Confidential trip memoir · Only authorized memories included',
                style: pw.TextStyle(font: bodyFont, fontSize: 7, color: TravelBookTheme.muted),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(font: bodyFont, fontSize: 7, color: TravelBookTheme.muted),
              ),
            ],
          ),
        ),
        build: (context) => [
          // Section: Journey Overview
          pw.Text(
            'CHAPTER I',
            style: pw.TextStyle(
              font: bodyBoldFont,
              fontSize: 8.5,
              letterSpacing: 2.0,
              color: TravelBookTheme.sand,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'The Journey in Review',
            style: pw.TextStyle(
              font: displayFont,
              fontSize: 22,
              color: TravelBookTheme.charcoal,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Over the course of ${replay.stats.daysRecorded} recorded days, our circle gathered in '
            '${replay.trip.destination}. This volume synthesizes confirmed itinerary milestones, '
            'unhurried personal reflections, and shared memories curated through the SAFAR Living Journey Network.',
            style: pw.TextStyle(
              font: bodyFont,
              fontSize: 10,
              color: TravelBookTheme.slate,
              lineSpacing: 1.4,
            ),
          ),
          pw.SizedBox(height: 16),

          // Financial Summary if available
          if (balances != null || (expenseTotals != null && expenseTotals.items.isNotEmpty)) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: TravelBookTheme.cardBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: TravelBookTheme.line, width: 0.6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'GROUP EXPENDITURE ARCHIVE',
                        style: pw.TextStyle(
                          font: bodyBoldFont,
                          fontSize: 8,
                          letterSpacing: 1.2,
                          color: TravelBookTheme.ember,
                        ),
                      ),
                      if (balances != null)
                        pw.Text(
                          'Total: ${balances.totalSpent.toStringAsFixed(2)} ${balances.currency}',
                          style: pw.TextStyle(
                            font: bodyBoldFont,
                            fontSize: 10,
                            color: TravelBookTheme.charcoal,
                          ),
                        ),
                    ],
                  ),
                  if (balances?.disclosure != null) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      balances!.disclosure,
                      style: pw.TextStyle(
                        font: bodyObliqueFont,
                        fontSize: 7.5,
                        color: TravelBookTheme.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 20),
          ],

          pw.Divider(color: TravelBookTheme.line, thickness: 0.6),
          pw.SizedBox(height: 14),

          // Section: Day-by-Day Chronicle
          pw.Text(
            'CHAPTER II',
            style: pw.TextStyle(
              font: bodyBoldFont,
              fontSize: 8.5,
              letterSpacing: 2.0,
              color: TravelBookTheme.sand,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Daily Chronicle & Shared Memories',
            style: pw.TextStyle(
              font: displayFont,
              fontSize: 22,
              color: TravelBookTheme.charcoal,
            ),
          ),
          pw.SizedBox(height: 14),

          if (replay.days.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: TravelBookTheme.cardBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'No recorded days or approved memories were found for this journey yet. '
                'As moments are approved in the Memory Studio, they will appear here.',
                style: pw.TextStyle(font: bodyObliqueFont, fontSize: 10, color: TravelBookTheme.muted),
              ),
            )
          else
            for (int i = 0; i < replay.days.length; i++)
              _buildDaySection(
                dayIndex: i + 1,
                day: replay.days[i],
                displayFont: displayFont,
                bodyFont: bodyFont,
                bodyBoldFont: bodyBoldFont,
                bodyObliqueFont: bodyObliqueFont,
              ),

          pw.SizedBox(height: 24),
          pw.Divider(color: TravelBookTheme.line, thickness: 0.6),
          pw.SizedBox(height: 16),

          // Closing Colophon
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: TravelBookTheme.cardBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: TravelBookTheme.line, width: 0.6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MEMOIR COLOPHON',
                  style: pw.TextStyle(
                    font: bodyBoldFont,
                    fontSize: 8,
                    letterSpacing: 1.5,
                    color: TravelBookTheme.sand,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'This travel book was rendered natively on-device by SAFAR. '
                  'Private memories and unapproved group drafts have been excluded according to the trip pact. '
                  'No personal data was transmitted to external print or layout services.',
                  style: pw.TextStyle(
                    font: bodyFont,
                    fontSize: 8.5,
                    color: TravelBookTheme.slate,
                    lineSpacing: 1.3,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Permissions Policy: ${replay.permissions}',
                  style: pw.TextStyle(
                    font: bodyObliqueFont,
                    fontSize: 7.5,
                    color: TravelBookTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildDaySection({
    required int dayIndex,
    required ReplayDay day,
    required pw.Font displayFont,
    required pw.Font bodyFont,
    required pw.Font bodyBoldFont,
    required pw.Font bodyObliqueFont,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 24),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Day Header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'DAY $dayIndex',
                style: pw.TextStyle(
                  font: bodyBoldFont,
                  fontSize: 10,
                  letterSpacing: 1.8,
                  color: TravelBookTheme.ember,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '·  ${formatDate(day.date)}',
                style: pw.TextStyle(
                  font: displayFont,
                  fontSize: 14,
                  color: TravelBookTheme.charcoal,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(height: 0.8, color: TravelBookTheme.line),
          pw.SizedBox(height: 10),

          // Itinerary Timeline
          if (day.items.isNotEmpty) ...[
            pw.Text(
              'ITINERARY MILESTONES',
              style: pw.TextStyle(
                font: bodyBoldFont,
                fontSize: 7.5,
                letterSpacing: 1.0,
                color: TravelBookTheme.muted,
              ),
            ),
            pw.SizedBox(height: 6),
            for (final item in day.items)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 6, bottom: 5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 48,
                      child: pw.Text(
                        formatClock(item.startTime),
                        style: pw.TextStyle(
                          font: bodyBoldFont,
                          fontSize: 8.5,
                          color: TravelBookTheme.ember,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        item.title,
                        style: pw.TextStyle(
                          font: bodyFont,
                          fontSize: 8.5,
                          color: TravelBookTheme.charcoal,
                        ),
                      ),
                    ),
                    if (item.protected)
                      pw.Text(
                        'protected',
                        style: pw.TextStyle(
                          font: bodyObliqueFont,
                          fontSize: 7,
                          color: TravelBookTheme.sand,
                        ),
                      ),
                  ],
                ),
              ),
            pw.SizedBox(height: 10),
          ],

          // Approved Events / Stories
          if (day.events.isNotEmpty) ...[
            for (final event in day.events)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: TravelBookTheme.cardBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: TravelBookTheme.line, width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          event.title,
                          style: pw.TextStyle(
                            font: displayFont,
                            fontSize: 11,
                            color: TravelBookTheme.charcoal,
                          ),
                        ),
                        pw.Text(
                          'APPROVED STORY',
                          style: pw.TextStyle(
                            font: bodyBoldFont,
                            fontSize: 6.5,
                            letterSpacing: 0.8,
                            color: TravelBookTheme.jade,
                          ),
                        ),
                      ],
                    ),
                    if (event.summary != null && event.summary!.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        event.summary!,
                        style: pw.TextStyle(
                          font: bodyFont,
                          fontSize: 8.5,
                          color: TravelBookTheme.slate,
                          lineSpacing: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],

          // Memories & Captions
          if (day.memories.isNotEmpty) ...[
            pw.Text(
              'SHARED MEMORIES & CAPTIONS',
              style: pw.TextStyle(
                font: bodyBoldFont,
                fontSize: 7.5,
                letterSpacing: 1.0,
                color: TravelBookTheme.muted,
              ),
            ),
            pw.SizedBox(height: 6),
            for (final mem in day.memories)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: pw.BoxDecoration(
                  border: const pw.Border(
                    left: pw.BorderSide(color: TravelBookTheme.ember, width: 2),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      mem.caption ?? mem.textContent ?? 'Shared memory',
                      style: pw.TextStyle(
                        font: bodyFont,
                        fontSize: 8.5,
                        color: TravelBookTheme.charcoal,
                        lineSpacing: 1.3,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '— ${mem.author?.displayName ?? 'Traveller'}  ·  ${formatClock(mem.capturedAt)}'
                      '${mem.kind != 'text' ? '  ·  ${mem.kind}' : ''}',
                      style: pw.TextStyle(
                        font: bodyObliqueFont,
                        fontSize: 7,
                        color: TravelBookTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _statItem(String label, String value, pw.Font font, pw.Font boldFont) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: 16,
            color: TravelBookTheme.charcoal,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          label,
          style: pw.TextStyle(
            font: font,
            fontSize: 6.5,
            letterSpacing: 0.8,
            color: TravelBookTheme.muted,
          ),
        ),
      ],
    );
  }

  static pw.Widget _dividerVertical() {
    return pw.Container(
      height: 24,
      width: 0.8,
      color: TravelBookTheme.line,
    );
  }
}
