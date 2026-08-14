import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';



class NotificationService {

  NotificationService._internal();


  static final NotificationService _instance = NotificationService._internal();


  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();


  final StreamController<String?> _payloadStreamController =
      StreamController<String?>.broadcast();


  Stream<String?> get onNotificationTap => _payloadStreamController.stream;


  FlutterLocalNotificationsPlugin get plugin => _localNotifications;



  Future<void> init() async {

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');


    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );


    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );


    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          _payloadStreamController.add(response.payload);
        }
      },
    );


    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {

      const AndroidNotificationChannel messageChannel = AndroidNotificationChannel(
        'Chhaya_message_channel',
        'Chhaya Messages',
        description: 'Heads-up notifications for secure incoming chat messages.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
        enableLights: true,
      );


      const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
        'Chhaya_call_channel',
        'Chhaya Calls',
        description: 'Urgent incoming audio and video call alerts.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
        enableLights: true,


      );


      await androidPlugin.createNotificationChannel(messageChannel);
      await androidPlugin.createNotificationChannel(callChannel);


      await androidPlugin.requestNotificationsPermission();
    }


  }


  Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'Chhaya_message_channel',
      'Chhaya Messages',
      channelDescription: 'Heads-up notifications for secure incoming chat messages.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,


    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,


    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }


  Future<void> showCallNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'Chhaya_call_channel',
      'Chhaya Calls',
      channelDescription: 'Urgent incoming audio and video call alerts.',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      playSound: true,
      enableVibration: true,


    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      categoryIdentifier: 'call_category',


    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }


  void dispose() {
    _payloadStreamController.close();
  }
}
