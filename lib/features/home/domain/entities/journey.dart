import 'package:equatable/equatable.dart';

class Journey extends Equatable {
  final String id;
  final String origin;
  final String destination;
  final DateTime date;
  final int memberCount;
  final String status;

  const Journey({
    required this.id,
    required this.origin,
    required this.destination,
    required this.date,
    required this.memberCount,
    required this.status,
  });

  String get title => "$origin -> $destination";
  
  String get formattedDate {
    // Basic formatting - in a real app use intl package
    final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "${months[date.month - 1]} ${date.day}";
  }

  @override
  List<Object?> get props => [id, origin, destination, date, memberCount, status];
}