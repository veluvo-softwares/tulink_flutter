// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_base.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApiResponseBase _$ApiResponseBaseFromJson(Map<String, dynamic> json) =>
    ApiResponseBase(
      success: json['success'] as bool,
      statusCode: (json['statusCode'] as num).toInt(),
      message: json['message'] as String,
      error: json['error'] == null
          ? null
          : ApiError.fromJson(json['error'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ApiResponseBaseToJson(ApiResponseBase instance) =>
    <String, dynamic>{
      'success': instance.success,
      'statusCode': instance.statusCode,
      'message': instance.message,
      'error': instance.error,
    };
