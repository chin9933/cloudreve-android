import 'dart:convert';
import 'dart:typed_data';

class SiteAuthConfig {
  const SiteAuthConfig({
    required this.registerEnabled,
    required this.registerCaptcha,
    required this.captchaType,
    this.termsUrl,
    this.privacyUrl,
  });
  final bool registerEnabled;
  final bool registerCaptcha;
  final String captchaType;
  final String? termsUrl;
  final String? privacyUrl;

  factory SiteAuthConfig.fromJson(
    Map<String, dynamic> basic,
    Map<String, dynamic> login,
  ) => SiteAuthConfig(
    registerEnabled: login['register_enabled'] == true,
    registerCaptcha: login['reg_captcha'] == true,
    captchaType: basic['captcha_type']?.toString() ?? 'normal',
    termsUrl: login['tos_url']?.toString(),
    privacyUrl: login['privacy_policy_url']?.toString(),
  );
}

class ImageCaptcha {
  const ImageCaptcha({required this.ticket, required this.bytes});
  final String ticket;
  final Uint8List bytes;

  factory ImageCaptcha.fromJson(Map<String, dynamic> json) {
    final image = json['image']?.toString() ?? '';
    final ticket = json['ticket']?.toString() ?? '';
    if (!image.startsWith('data:image/') || ticket.isEmpty) {
      throw const FormatException('服务器未返回有效的图片验证码');
    }
    return ImageCaptcha(
      ticket: ticket,
      bytes: base64Decode(image.substring(image.indexOf(',') + 1)),
    );
  }
}
