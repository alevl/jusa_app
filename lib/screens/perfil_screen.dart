import 'package:flutter/material.dart';
import 'editar_perfil_screen.dart';

class PerfilScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final Function(Map<String, dynamic>)? onPerfilActualizado;

  const PerfilScreen({
    super.key,
    required this.usuario,
    this.onPerfilActualizado,
  });

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  late Map<String, dynamic> usuarioLocal;

  @override
  void initState() {
    super.initState();
    usuarioLocal = Map<String, dynamic>.from(widget.usuario);
  }

  @override
  void didUpdateWidget(covariant PerfilScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.usuario != widget.usuario) {
      setState(() {
        usuarioLocal = Map<String, dynamic>.from(widget.usuario);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String nombreAMostrar =
        usuarioLocal["name"] ?? usuarioLocal["nombre"] ?? "No definido";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Mi Perfil",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF424949),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    // ✅ CORRECCIÓN: Uso de withValues para evitar la depreciación
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Image.asset(
                  "assets/images/logo-jusa-2-opt.png",
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.grey,
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          _buildInfoCard(Icons.person, "Nombre completo", nombreAMostrar),
          _buildInfoCard(
            Icons.account_circle,
            "Usuario de acceso",
            usuarioLocal["username"] ?? "Sin usuario",
          ),
          _buildInfoCard(
            Icons.phone,
            "Número de contacto",
            usuarioLocal["telefono"] ?? "Sin teléfono",
          ),
          _buildInfoCard(
            Icons.business,
            "PLAZA",
            usuarioLocal["plaza"] ?? "No definida",
          ),
          _buildInfoCard(
            Icons.location_on,
            "UBICACION",
            usuarioLocal["ubicacion"] ?? "No definida",
          ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.edit, color: Colors.white),
              label: const Text(
                "EDITAR PERFIL",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditarPerfilScreen(
                      userId: usuarioLocal["id"],
                      nombreActual:
                          nombreAMostrar == "No definido" ? "" : nombreAMostrar,
                      telefonoActual: usuarioLocal["telefono"] ?? "",
                    ),
                  ),
                );

                if (!mounted) return;

                if (result != null && result is Map<String, dynamic>) {
                  if (widget.onPerfilActualizado != null) {
                    widget.onPerfilActualizado!(result);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              // ✅ CORRECCIÓN: Actualizado a withValues
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.green),
          ),
          title: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        const Divider(thickness: 0.5, height: 1),
      ],
    );
  }
}
