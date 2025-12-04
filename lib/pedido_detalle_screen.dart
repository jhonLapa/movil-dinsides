import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chat_screen.dart';

class PedidoDetalleScreen extends StatefulWidget {
  final String idPedido;
  final String miIdActual;
  final String miRolActual; // Ej: "motorizado", "cliente", "admin"

  const PedidoDetalleScreen({
    super.key,
    required this.idPedido,
    required this.miIdActual,
    required this.miRolActual,
  });

  @override
  State<PedidoDetalleScreen> createState() => _PedidoDetalleScreenState();
}

class _PedidoDetalleScreenState extends State<PedidoDetalleScreen> {
  bool _isLoading = false;

  // ⭐⭐ CAMBIO 1: Ahora la función recibe el "rolObjetivo" (con quién quiero hablar)
  Future<void> _abrirChat(String rolObjetivo) async {
    setState(() {
      _isLoading = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ⭐⭐ CAMBIO 2: Enviamos 'rol_objetivo' a tu PHP para que sepa qué chat buscar
      // Si soy motorizado y pido 'cliente', el PHP debe buscar el chat del pedido entre motorizado y cliente.
      final url = Uri.parse(
          'https://test.dinsidescourier.com/buscar_o_crear_chat_por_pedido.php?id_pedido=${widget.idPedido}&rol_objetivo=$rolObjetivo');

      final response =
          await http.get(url).timeout(const Duration(seconds: 60));

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final jsonResponse = jsonDecode(response.body);

      if (jsonResponse['success'] == true) {
        final String idConversacion = jsonResponse['id_conversacion'].toString();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                idConversacion: idConversacion,
                miId: widget.miIdActual,
                miTipo: widget.miRolActual,
                idPedido: widget.idPedido,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Error al iniciar chat: ${jsonResponse['message']}')),
          );
        }
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de red: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Normalizamos el rol a minúsculas para evitar errores (ej: "Motorizado" vs "motorizado")
    final String rolNormalizado = widget.miRolActual.toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: Text('Detalles del Pedido #${widget.idPedido}'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Aquí van los detalles de tu pedido.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            
            if (_isLoading)
              const CircularProgressIndicator()
            else
              // ⭐⭐ CAMBIO 3: Lógica condicional para mostrar botones
              Column(
                children: [
                  // CASO A: SI SOY MOTORIZADO
                  if (rolNormalizado == 'motorizado') ...[
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person),
                      label: const Text('Chat con Cliente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, // Color distintivo
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      ),
                      // Le decimos a la función que queremos hablar con el 'cliente'
                      onPressed: () => _abrirChat('cliente'),
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.support_agent),
                      label: const Text('Chat con Asesor'), // Soporte
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange, // Color distintivo
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      ),
                      // Le decimos a la función que queremos hablar con el 'asesor'
                      onPressed: () => _abrirChat('asesor'),
                    ),
                  ]
                  // CASO B: SI SOY CLIENTE
                  else if (rolNormalizado == 'cliente') ...[
                     ElevatedButton.icon(
                      icon: const Icon(Icons.motorcycle),
                      label: const Text('Chat con Motorizado'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      ),
                      onPressed: () => _abrirChat('motorizado'),
                    ),
                    // Si el cliente también necesita hablar con soporte, agregas otro botón aquí
                  ]
                  // CASO C: CUALQUIER OTRO ROL
                  else ...[
                    const Text("Rol no definido para chats")
                  ]
                ],
              ),
          ],
        ),
      ),
    );
  }
}