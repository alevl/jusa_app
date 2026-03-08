import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EditarPerfilScreen extends StatefulWidget {
  final int userId;
  final String nombreActual;
  final String telefonoActual;

  const EditarPerfilScreen({
    super.key,
    required this.userId,
    required this.nombreActual,
    required this.telefonoActual,
  });

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.nombreActual);
    _phoneCtrl = TextEditingController(text: widget.telefonoActual);
  }

  Future<void> _update() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);

    try {
      final response = await http.patch(
        Uri.parse(
            "https://sistema.jusaimpulsemkt.com/api/editar-usuario-app/${widget.userId}"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: json.encode({
          "name": _nameCtrl.text.trim(),
          "telefono": _phoneCtrl.text.trim(),
        }),
      );

      if (!mounted) {
        return;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✅ Actualizado"), backgroundColor: Colors.green));
        Navigator.pop(context, data["user"]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("❌ Error al guardar"), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Editar Perfil",
            style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF424949),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text("Actualiza tu información personal",
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 25),
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: "Nombre Completo",
                prefixIcon: const Icon(Icons.person),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return "Obligatorio";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: "Teléfono",
                prefixIcon: const Icon(Icons.phone),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return "Obligatorio";
                }
                return null;
              },
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _update,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text("GUARDAR CAMBIOS",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
