/// Query parameter builder for API endpoints
/// Handles pagination, search, and filtering logic
class ApiQueryBuilder {
  ApiQueryBuilder._();

  /// Constructs paginated endpoint with query parameters
  static String paginated(String baseEndpoint, {
    int? page,
    int? limit,
    String? sortBy,
    String? sortOrder,
  }) {
    final buffer = StringBuffer(baseEndpoint);
    final queryParams = <String>[];

    if (page != null) queryParams.add('page=$page');
    if (limit != null) queryParams.add('limit=$limit');
    if (sortBy != null) queryParams.add('sortBy=$sortBy');
    if (sortOrder != null) queryParams.add('sortOrder=$sortOrder');

    if (queryParams.isNotEmpty) {
      buffer.write('?${queryParams.join('&')}');
    }

    return buffer.toString();
  }

  /// Constructs search endpoint with query parameters
  static String search(String baseEndpoint, {
    required String query,
    List<String>? filters,
    int? page,
    int? limit,
  }) {
    final buffer = StringBuffer(baseEndpoint);
    final queryParams = <String>['q=${Uri.encodeComponent(query)}'];

    if (filters != null && filters.isNotEmpty) {
      for (final filter in filters) {
        queryParams.add('filter=${Uri.encodeComponent(filter)}');
      }
    }
    if (page != null) queryParams.add('page=$page');
    if (limit != null) queryParams.add('limit=$limit');

    buffer.write('?${queryParams.join('&')}');
    return buffer.toString();
  }

  /// Add query parameters to any endpoint
  static String withParams(String endpoint, Map<String, dynamic> params) {
    if (params.isEmpty) return endpoint;
    
    final buffer = StringBuffer(endpoint);
    final queryParams = <String>[];

    params.forEach((key, value) {
      if (value != null) {
        queryParams.add('$key=${Uri.encodeComponent(value.toString())}');
      }
    });

    if (queryParams.isNotEmpty) {
      final separator = endpoint.contains('?') ? '&' : '?';
      buffer.write('$separator${queryParams.join('&')}');
    }

    return buffer.toString();
  }

  /// Build filter parameters
  static Map<String, dynamic> buildFilters({
    String? category,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? tags,
  }) {
    final filters = <String, dynamic>{};
    
    if (category != null) filters['category'] = category;
    if (status != null) filters['status'] = status;
    if (startDate != null) filters['startDate'] = startDate.toIso8601String();
    if (endDate != null) filters['endDate'] = endDate.toIso8601String();
    if (tags != null && tags.isNotEmpty) filters['tags'] = tags.join(',');
    
    return filters;
  }
}