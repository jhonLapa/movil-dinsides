import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

String? currentSessionId;
// Guardamos la última posición para saber si nos movimos
double? lastLat;
double? lastLng;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // 1. INICIALIZAR FIREBASE
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Ignorar si ya está listo
  }

  // 2. CONFIGURAR NOTIFICACIONES
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('ic_launcher');

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground',
    'SEGUIMIENTO COURIER',
    description: 'Actualizando ubicación en tiempo real',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // 3. LISTENERS
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('startTracking').listen((event) {
    if (event != null && event.containsKey('sessionId')) {
      currentSessionId = event['sessionId'];
      print("✅ ID RECIBIDO: $currentSessionId");
      
      flutterLocalNotificationsPlugin.show(
        888,
        'CONECTADO 🟢',
        'Esperando movimiento...',
        const NotificationDetails(
            android: AndroidNotificationDetails(
                'my_foreground', 'SEGUIMIENTO COURIER',
                icon: 'ic_launcher', ongoing: true, playSound: false)),
      );
    }
  });

  // 4. 🔥 ESTRATEGIA DE FUERZA BRUTA (POLLING) 🔥
  // Ejecutamos esto CADA SEGUNDO sin falta.
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        
        // Si no hay ID, esperamos
        if (currentSessionId == null) return;

        Position? position;

        try {
          // Configuración ESPECÍFICA para que Lockito funcione
          final LocationSettings locationSettings = AndroidSettings(
            accuracy: LocationAccuracy.best, // Máxima precisión
            distanceFilter: 0, 
            forceLocationManager: true, // <--- OBLIGATORIO PARA LOCKITO
            intervalDuration: const Duration(seconds: 1),
          );

          // FORZAMOS LA LECTURA (No esperamos un stream)
          position = await Geolocator.getCurrentPosition(
            locationSettings: locationSettings,
          );
        } catch (e) {
          print("Error GPS: $e");
        }

        if (position != null) {
          // Verificamos si realmente nos movimos (para no saturar si está quieto)
          // Pero actualizamos la notificación para que veas que está vivo
          
          bool seMovio = (lastLat != position.latitude || lastLng != position.longitude);
          lastLat = position.latitude;
          lastLng = position.longitude;

          // A. NOTIFICACIÓN DE DIAGNÓSTICO (Mira los números cambiar)
          flutterLocalNotificationsPlugin.show(
            888,
            'Rastreando 🛰️',
            'Lat: ${position.latitude.toStringAsFixed(5)} \nVel: ${(position.speed * 3.6).toStringAsFixed(1)} km/h',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'my_foreground',
                'SEGUIMIENTO COURIER',
                icon: 'ic_launcher',
                ongoing: true,
                playSound: false,
                onlyAlertOnce: true,
              ),
            ),
          );

          // B. ENVIAR A LA UI
          service.invoke('update', {
            "lat": position.latitude,
            "lng": position.longitude,
          });

          // C. GUARDAR EN FIREBASE (Solo si hay ID)
          // Lo hacemos siempre para actualizar el timestamp y que no salga "Desconocido"
          try {
            await FirebaseFirestore.instance
                .collection('active_locations')
                .doc(currentSessionId)
                .set({
              'latitude': position.latitude,
              'longitude': position.longitude,
              'heading': position.heading,
              'speed': position.speed,
              'lastUpdated': FieldValue.serverTimestamp(),
              'status': 'active',
            }, SetOptions(merge: true));
            
            if (seMovio) {
              print("🚀 GPS NUEVO -> Firebase actualizado: ${position.latitude}");
            }
          } catch (e) {
            print("Error Firebase: $e");
          }
        }
      }
    }
  });
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground',
    'SEGUIMIENTO COURIER',
    description: 'Ubicación en vivo',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Conectando...',
      initialNotificationContent: 'Iniciando GPS',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}