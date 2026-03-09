import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'photo_gallery_screen.dart';
import 'perfil_screen.dart';

class DashboardScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final int nivelId;
  final List<dynamic> fotosServidor;

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.nivelId,
    required this.fotosServidor,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Logger logger = Logger();
  bool _loading = true;
  bool _sendingPhoto = false;
  List<dynamic> _asignaciones = [];
  late Map<String, dynamic> _userData;

  @override
  void initState() {
    super.initState();
    _userData = {
      "id": widget.userId,
      "name": widget.userName,
      "username": widget.userName,
      "nivel_id": widget.nivelId,
      "telefono": "---",
      "cliente": "Cargando...",
    };
    _fetchAsignaciones();
  }

  String _obtenerTituloEncabezado() {
    if (widget.nivelId == 3) {
      return "TOMAR FOTOS";
    } else {
      return "REPORTE FOTOGRÁFICO";
    }
  }

  // --- LÓGICA DE GEOLOCALIZACIÓN Y FOTOS ---

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('El GPS está desactivado.');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Permiso denegado.');
      }
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<File> _addWatermark(File imageFile, Position pos) async {
    final bytes = await imageFile.readAsBytes();
    img.Image? originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      return imageFile;
    }

    String timestamp = DateTime.now().toString().split('.')[0];
    String text =
        "LAT: ${pos.latitude.toStringAsFixed(6)}\nLON: ${pos.longitude.toStringAsFixed(6)}\nFECHA: $timestamp";

    img.drawString(originalImage, text,
        font: img.arial24,
        x: 30,
        y: originalImage.height - 140,
        color: img.ColorRgba8(255, 255, 255, 255));

    final tempDir = await getTemporaryDirectory();
    final path =
        "${tempDir.path}/marked_${DateTime.now().millisecondsSinceEpoch}.jpg";
    final File markedFile = File(path);
    await markedFile.writeAsBytes(img.encodeJpg(originalImage, quality: 90));
    return markedFile;
  }

  // --- PETICIONES API ---

  Future<void> _fetchAsignaciones() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
    });

    String apiUrl = "";
    if (widget.nivelId == 2) {
      apiUrl =
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-supervisor-app/${widget.userId}";
    } else if (widget.nivelId == 4) {
      apiUrl =
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-cliente-app/${widget.userId}";
    } else {
      apiUrl =
          "https://sistema.jusaimpulsemkt.com/api/mis-asignaciones-app/${widget.userId}";
    }

    try {
      final response = await http.get(Uri.parse(apiUrl), headers: const {
        "Accept": "application/json"
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _asignaciones = data["datos"] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint("Error Fetch Dashboard: $e");
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _takePhoto(dynamic asignacion) async {
    Position? currentPosition;
    try {
      currentPosition = await _determinePosition();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("GPS: $e")));
      }
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? photo =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null || !mounted) {
      return;
    }

    setState(() {
      _sendingPhoto = true;
    });

    try {
      File markedFile = await _addWatermark(File(photo.path), currentPosition);
      final request = http.MultipartRequest('POST',
          Uri.parse("https://sistema.jusaimpulsemkt.com/api/tomar-foto-app"));
      request.fields['asignacion_id'] = asignacion["id"].toString();
      request.fields['latitud'] = currentPosition.latitude.toString();
      request.fields['longitud'] = currentPosition.longitude.toString();
      request.files
          .add(await http.MultipartFile.fromPath('file', markedFile.path));

      final response = await request.send();
      if (mounted && response.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("✅ Foto enviada")));
        _fetchAsignaciones();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("❌ Error al enviar")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingPhoto = false;
        });
      }
    }
  }

  Future<void> _viewPhotos(dynamic asignacion) async {
    try {
      final response = await http.get(Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/fotos-asignacion-app/${asignacion["id"]}"));
      if (mounted && response.statusCode == 200) {
        final List fotos = json.decode(response.body)["datos"] ?? [];
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PhotoGalleryScreen(
                      fotosServidor: fotos,
                      asignacion: asignacion,
                      nivelId: widget.nivelId,
                    )));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Error galería")));
      }
    }
  }

  void _abrirPerfil() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => PerfilScreen(
                  usuario: _userData,
                  onPerfilActualizado: (datosNuevos) {
                    if (mounted) {
                      setState(() {
                        _userData = datosNuevos;
                      });
                    }
                  },
                )));
  }

  // --- INTERFAZ ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF424949),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_obtenerTituloEncabezado(),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                GestureDetector(
                  onTap: _abrirPerfil,
                  child: Image.asset("assets/images/logo-jusa-2-opt.png",
                      height: 60),
                ),
                const SizedBox(height: 10),
                Text("Bienvenido: ${widget.userName}",
                    style: const TextStyle(
                        color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Expanded(child: _buildMainContent()),
              ],
            ),
          ),
          if (_sendingPhoto)
            Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_asignaciones.isEmpty) {
      return RefreshIndicator(
          onRefresh: _fetchAsignaciones,
          child: ListView(children: const [
            SizedBox(height: 50),
            Center(child: Text("NO HAY ASIGNACIONES"))
          ]));
    }

    return RefreshIndicator(
      onRefresh: _fetchAsignaciones,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _asignaciones.length,
        itemBuilder: (context, index) {
          final asign = _asignaciones[index];

          // ✅ CAMBIO SOLICITADO: Priorizamos el campo "ruta" para la etiqueta Ubicación
          final String ubicacionFinal = asign["ruta"] ??
              asign["municipio"] ??
              asign["ubicación"] ??
              asign["ubicacion"] ??
              asign["sucursal"] ??
              asign["plaza"] ??
              asign["direccion"] ??
              "S/D";

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow("Fecha:", asign["fecha"]),
                        _infoRow("Hora:", asign["hora"] ?? "S/H"),
                        _infoRow("Cliente:", asign["cliente"]),
                        _infoRow("Plaza:",
                            asign["plaza"] ?? asign["sucursal"] ?? "N/A"),
                        // ✅ Aquí se muestra el valor de RUTA
                        _infoRow("Ubicación:", ubicacionFinal),
                        _infoRow("Estatus:", asign["estatus"], highlight: true),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.nivelId == 3) ...[
                        IconButton(
                          icon: const Icon(Icons.camera_alt,
                              color: Colors.green, size: 30),
                          onPressed: () => _takePhoto(asign),
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.photo_library,
                            color: Colors.blue, size: 30),
                        onPressed: () => _viewPhotos(asign),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, dynamic value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black, fontSize: 13),
          children: [
            TextSpan(
                text: "$label ",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(
              text: "${value ?? 'N/A'}",
              style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                color: highlight ? Colors.blueGrey : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
} //dashboard_screen.dart//
