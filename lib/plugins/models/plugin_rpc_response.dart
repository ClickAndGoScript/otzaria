class PluginRpcResponse {
  final bool success;
  final dynamic data;
  final PluginRpcError? error;

  const PluginRpcResponse._({
    required this.success,
    this.data,
    this.error,
  });

  const PluginRpcResponse.success(dynamic data)
      : this._(success: true, data: data);

  PluginRpcResponse.error({
    required String code,
    required String message,
  }) : this._(
          success: false,
          error: PluginRpcError(code: code, message: message),
        );

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'data': success ? data : null,
      'error': success ? null : error?.toJson(),
    };
  }
}

class PluginRpcError {
  final String code;
  final String message;

  const PluginRpcError({
    required this.code,
    required this.message,
  });

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
    };
  }
}
