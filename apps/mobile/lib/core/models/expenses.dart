import 'common.dart';
import 'json.dart';

class ExpenseParticipant {
  const ExpenseParticipant({
    required this.id,
    required this.weight,
    required this.shareAmount,
    this.user,
    this.guestName,
  });

  final String id;
  final double weight;
  final double shareAmount;
  final User? user;
  final String? guestName;

  String get displayName =>
      user?.displayName ?? guestName ?? 'Guest';

  factory ExpenseParticipant.fromJson(Map<String, dynamic> json) {
    final userJson = jsonMap(json['user']);
    return ExpenseParticipant(
      id: jsonText(json['id']),
      weight: jsonDouble(json['weight'], 1),
      shareAmount: jsonDouble(json['share_amount']),
      user: userJson.isEmpty ? null : User.fromJson(userJson),
      guestName: jsonString(json['guest_name']),
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.currency,
    required this.paidBy,
    required this.incurredOn,
    this.payer,
    this.notes,
    this.participants = const [],
  });

  final String id;
  final String title;
  final String category;
  final double amount;
  final String currency;
  final String paidBy;
  final String incurredOn;
  final User? payer;
  final String? notes;
  final List<ExpenseParticipant> participants;

  factory Expense.fromJson(Map<String, dynamic> json) {
    final payerJson = jsonMap(json['payer']);
    return Expense(
      id: jsonText(json['id']),
      title: jsonText(json['title']),
      category: jsonText(json['category'], 'other'),
      amount: jsonDouble(json['amount']),
      currency: jsonText(json['currency'], 'EUR'),
      paidBy: jsonText(json['paid_by']),
      incurredOn: jsonText(json['incurred_on']),
      payer: payerJson.isEmpty ? null : User.fromJson(payerJson),
      notes: jsonString(json['notes']),
      participants: jsonObjects(
        json['participants'],
        ExpenseParticipant.fromJson,
      ),
    );
  }
}

class ExpenseTotals {
  const ExpenseTotals({
    required this.items,
    required this.totals,
  });

  final List<Expense> items;
  final Map<String, double> totals;

  factory ExpenseTotals.fromJson(Map<String, dynamic> json) {
    final totals = <String, double>{};
    jsonMap(json['totals']).forEach((key, value) {
      totals[key] = jsonDouble(value);
    });
    return ExpenseTotals(
      items: jsonObjects(json['items'], Expense.fromJson),
      totals: totals,
    );
  }
}

class Balance {
  const Balance({
    required this.userId,
    required this.displayName,
    required this.net,
  });

  final String userId;
  final String displayName;
  final double net;

  factory Balance.fromJson(Map<String, dynamic> json) => Balance(
    userId: jsonText(json['user_id']),
    displayName: jsonText(json['display_name']),
    net: jsonDouble(json['net']),
  );
}

class Settlement {
  const Settlement({
    required this.fromUserId,
    required this.fromName,
    required this.toUserId,
    required this.toName,
    required this.amount,
  });

  final String fromUserId;
  final String fromName;
  final String toUserId;
  final String toName;
  final double amount;

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
    fromUserId: jsonText(json['from_user_id']),
    fromName: jsonText(json['from_name']),
    toUserId: jsonText(json['to_user_id']),
    toName: jsonText(json['to_name']),
    amount: jsonDouble(json['amount']),
  );
}

class BalancesResponse {
  const BalancesResponse({
    required this.totalSpent,
    required this.currency,
    required this.balances,
    required this.settlements,
    required this.disclosure,
  });

  final double totalSpent;
  final String currency;
  final List<Balance> balances;
  final List<Settlement> settlements;
  final String disclosure;

  factory BalancesResponse.fromJson(Map<String, dynamic> json) =>
      BalancesResponse(
        totalSpent: jsonDouble(json['total_spent']),
        currency: jsonText(json['currency'], 'EUR'),
        balances: jsonObjects(json['balances'], Balance.fromJson),
        settlements: jsonObjects(json['settlements'], Settlement.fromJson),
        disclosure: jsonText(json['disclosure']),
      );
}
