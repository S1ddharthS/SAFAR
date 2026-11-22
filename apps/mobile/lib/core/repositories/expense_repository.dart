import '../models/expenses.dart';
import '../models/json.dart';
import '../network/api_client.dart';

class ExpenseRepository {
  ExpenseRepository(this._api);

  final ApiClient _api;

  Future<ExpenseTotals> list(String tripId) async =>
      ExpenseTotals.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/expenses')),
      );

  Future<BalancesResponse> balances(String tripId) async =>
      BalancesResponse.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/expenses/balances')),
      );

  Future<void> create(
    String tripId, {
    required String title,
    required double amount,
    String category = 'other',
    String? paidBy,
    String? incurredOn,
    String? notes,
    String split = 'equal',
  }) async {
    await _api.post(
      '/api/trips/$tripId/expenses',
      data: {
        'title': title,
        'category': category,
        'amount': amount,
        'paid_by': ?paidBy,
        'incurred_on': ?incurredOn,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'split': split,
      },
    );
  }

  Future<void> delete(String tripId, String expenseId) async {
    await _api.delete('/api/trips/$tripId/expenses/$expenseId');
  }

  Future<String> exportCsv(String tripId) async =>
      (await _api.get('/api/trips/$tripId/expenses/export', raw: true))
          .toString();
}
