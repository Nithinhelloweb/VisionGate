import 'package:flutter/foundation.dart';

class LeaveBalanceNotifier extends ChangeNotifier {
  static final LeaveBalanceNotifier instance = LeaveBalanceNotifier._internal();

  LeaveBalanceNotifier._internal();

  void notifyBalanceChanged() {
    notifyListeners();
  }
}
