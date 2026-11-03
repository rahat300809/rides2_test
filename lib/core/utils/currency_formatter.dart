class CurrencyFormatter {
  CurrencyFormatter._();

  /// Formats amount in Bangladeshi Taka (BDT / ৳)
  static String formatBdt(num amount) {
    if (amount % 1 == 0) {
      return '৳${amount.toInt()}';
    }
    return '৳${amount.toStringAsFixed(2)}';
  }
}
