class SecurityState {
  const SecurityState({
    required this.saltBase64,
    required this.verifierBase64,
    required this.iterations,
  });

  final String saltBase64;
  final String verifierBase64;
  final int iterations;

  Map<String, dynamic> toJson() {
    return {
      'saltBase64': saltBase64,
      'verifierBase64': verifierBase64,
      'iterations': iterations,
    };
  }

  factory SecurityState.fromJson(Map<String, dynamic> json) {
    return SecurityState(
      saltBase64: json['saltBase64'] as String,
      verifierBase64: json['verifierBase64'] as String,
      iterations: json['iterations'] as int,
    );
  }
}
