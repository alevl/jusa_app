import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

// --- IMPORTACIONES LOCALES ---
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
  bool _loading = false;
  bool _sendingPhoto = false;
  List<dynamic> _asignaciones = [];
  late Map<String, dynamic> _userData;

  List<dynamic> _clientes = [];
  List<dynamic> _supervisores = [];
  List<dynamic> _tipos = [];

  String _selectedCliente = "0";
  String _selectedSupervisor = "0";
  String _selectedTipo = "0";

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

    _inicializarDatos();
  }

  Future<void> _inicializarDatos() async {
    if (widget.nivelId == 5) {
      await Future.wait([
        _fetchListaClientes(),
        _fetchListaTipos(),
      ]);
    } else {
      await _fetchAsignaciones();
    }
  }

  String _obtenerTituloEncabezado() {
    if (widget.nivelId == 3) {
      return "PANEL CHOFER";
    }
    if (widget.nivelId == 2) {
      return "PANEL SUPERVISOR";
    }
    if (widget.nivelId == 5) {
      return "PANEL ASISTENTE";
    }
    return "REPORTE FOTOGRÁFICO";
  }

  // --- PETICIONES API ---

  Future<void> _fetchListaClientes() async {
    try {
      final response = await http.get(Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/lista-clientes-app"));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _clientes = json.decode(response.body)["datos"] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error Clientes: $e");
    }
  }

  Future<void> _fetchListaSupervisores(String clienteId) async {
    if (clienteId == "0") {
      setState(() {
        _supervisores = [];
        _selectedSupervisor = "0";
      });
      return;
    }
    try {
      final response = await http.get(Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/lista-supervisores-app/$clienteId"));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _supervisores = json.decode(response.body)["datos"] ?? [];
          _selectedSupervisor = "0";
        });
      }
    } catch (e) {
      debugPrint("Error Supervisores: $e");
    }
  }

  Future<void> _fetchListaTipos() async {
    try {
      final response = await http.get(
          Uri.parse("https://sistema.jusaimpulsemkt.com/api/lista-tipos-app"));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _tipos = json.decode(response.body)["datos"] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error Tipos: $e");
    }
  }

  Future<void> _fetchAsignaciones() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _asignaciones = [];
    });

    String apiUrl = "";
    if (widget.nivelId == 5) {
      apiUrl =
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-asistente-app/$_selectedCliente/$_selectedSupervisor/$_selectedTipo";
    } else {
      String path = "mis-asignaciones-app";
      if (widget.nivelId == 2) {
        path = "asignaciones-supervisor-app";
      }
      if (widget.nivelId == 4) {
        path = "asignaciones-cliente-app";
      }
      apiUrl = "https://sistema.jusaimpulsemkt.com/api/$path/${widget.userId}";
    }

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _asignaciones = json.decode(response.body)["datos"] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error Fetch: $e");
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // --- LÓGICA DE FOTOS Y MARCA DE AGUA ---

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('GPS desactivado');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Permiso denegado');
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
    final File markedFile = File(
        "${tempDir.path}/marked_${DateTime.now().millisecondsSinceEpoch}.jpg");
    await markedFile.writeAsBytes(img.encodeJpg(originalImage, quality: 90));
    return markedFile;
  }

  Future<void> _takePhoto(dynamic asignacion) async {
    Position pos;
    try {
      pos = await _determinePosition();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("$e")));
      }
      return;
    }
    final XFile? photo = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null || !mounted) {
      return;
    }
    setState(() => _sendingPhoto = true);
    try {
      File markedFile = await _addWatermark(File(photo.path), pos);
      final request = http.MultipartRequest('POST',
          Uri.parse("https://sistema.jusaimpulsemkt.com/api/tomar-foto-app"));
      request.fields['asignacion_id'] = asignacion["id"].toString();
      request.fields['latitud'] = pos.latitude.toString();
      request.fields['longitud'] = pos.longitude.toString();
      request.files
          .add(await http.MultipartFile.fromPath('file', markedFile.path));
      final response = await request.send();
      if (mounted && response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Foto enviada correctamente")));
        _fetchAsignaciones();
      }
    } finally {
      if (mounted) {
        setState(() => _sendingPhoto = false);
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
                    nivelId: widget.nivelId)));
      }
    } catch (e) {
      debugPrint("Error Galería: $e");
    }
  }

  void _abrirPerfil() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => PerfilScreen(
                usuario: _userData,
                onPerfilActualizado: (datos) {
                  if (mounted) {
                    setState(() => _userData = datos);
                  }
                })));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF424949),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_obtenerTituloEncabezado(),
            style: const TextStyle(fontSize: 18, color: Colors.white)),
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
                        height: 60)),
                const SizedBox(height: 10),
                Text("Bienvenido: ${widget.userName}",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                if (widget.nivelId == 5) ...{
                  _buildPanelFiltrosAsistente(),
                },
                Expanded(child: _buildMainContent()),
              ],
            ),
          ),
          if (_sendingPhoto) ...{
            Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator())),
          },
        ],
      ),
    );
  }

  Widget _buildPanelFiltrosAsistente() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _buildDropdownFiltro(
                      label: "CLIENTE",
                      value: _selectedCliente,
                      items: _clientes,
                      idKey: "cliente_id",
                      nameKey: "name",
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedCliente = val;
                            _selectedSupervisor = "0";
                            _supervisores = [];
                          });
                          _fetchListaSupervisores(val);
                        }
                      })),
              Expanded(
                  child: _buildDropdownFiltro(
                      label: "SUPERVISOR",
                      value: _selectedSupervisor,
                      items: _supervisores,
                      idKey: "id",
                      nameKey: "name",
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedSupervisor = val);
                        }
                      })),
            ],
          ),
          Row(
            children: [
              Expanded(
                  child: _buildDropdownFiltro(
                      label: "TIPO",
                      value: _selectedTipo,
                      items: _tipos,
                      idKey: "id",
                      nameKey: "nombre",
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedTipo = val);
                        }
                      })),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
              onPressed: _fetchAsignaciones,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text("MOSTRAR")),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildDropdownFiltro(
      {required String label,
      required String value,
      required List<dynamic> items,
      required String idKey,
      required String nameKey,
      required ValueChanged<String?> onChanged}) {
    return Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blueGrey.shade100)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                style: const TextStyle(fontSize: 12, color: Colors.black),
                items: [
                  DropdownMenuItem<String>(
                      value: "0",
                      child: Text("TODOS ($label)",
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  ...items.map((item) => DropdownMenuItem<String>(
                      value: item[idKey].toString(),
                      child: Text(item[nameKey] ?? "Sin nombre")))
                ],
                onChanged: onChanged)));
  }

  Widget _buildMainContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_asignaciones.isEmpty) {
      return RefreshIndicator(
          onRefresh: _fetchAsignaciones,
          child: ListView(children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            const Center(child: Text("No Hay Registros Disponibles"))
          ]));
    }

    return RefreshIndicator(
      onRefresh: _fetchAsignaciones,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _asignaciones.length,
        itemBuilder: (context, index) {
          final asign = _asignaciones[index];
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
                        _infoRow("Hora:", asign["hora"]),
                        _infoRow("Cliente:", asign["cliente"]),
                        // --- PLAZA COLOCADA DESPUÉS DE CLIENTE ---
                        _infoRow("Plaza:", asign["plaza"]),
                        _infoRow("Ubicación:",
                            asign["ruta"] ?? asign["ubicacion"] ?? "S/D"),
                        _infoRow("Estatus:", asign["estatus"], highlight: true),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      if (widget.nivelId == 3 || widget.nivelId == 2) ...{
                        IconButton(
                            icon: const Icon(Icons.camera_alt,
                                color: Colors.green, size: 28),
                            onPressed: () => _takePhoto(asign)),
                      },
                      if (widget.nivelId == 2 ||
                          widget.nivelId == 3 ||
                          widget.nivelId == 4 ||
                          widget.nivelId == 5) ...{
                        IconButton(
                            icon: const Icon(Icons.photo_library,
                                color: Colors.blue, size: 28),
                            onPressed: () => _viewPhotos(asign)),
                      },
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
                    color: highlight ? Colors.blueGrey : Colors.black87))
          ])),
    );
  }
}
