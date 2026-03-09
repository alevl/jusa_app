import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

class PhotoGalleryScreen extends StatefulWidget {
  final List<dynamic>? fotosServidor;
  final dynamic asignacion;
  final int? nivelId;

  static const String baseImageUrl =
      "https://sistema.jusaimpulsemkt.com/storage/";

  const PhotoGalleryScreen({
    super.key,
    required this.fotosServidor,
    required this.asignacion,
    this.nivelId,
  });

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late List<dynamic> fotos;
  bool _cargandoTiempos = true;
  bool _actualizando = false;
  String _direccionEscrita = "Buscando dirección física...";

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  late LatLng _ubicacionInicial = const LatLng(0, 0);
  final Set<Marker> _markers = {};

  final String _googleMapsApiKey = "AIzaSyC-aarw02OP9iW4pwHoOlbZ2njidcJY82I";

  @override
  void initState() {
    super.initState();
    fotos =
        widget.fotosServidor != null ? List.from(widget.fotosServidor!) : [];
    _inicializarPantalla();
  }

  String _limpiar(dynamic valor) {
    if (valor == null) return "";
    return valor.toString().trim().replaceAll(RegExp(r'[\n\r\t]'), '');
  }

  void _inicializarPantalla() {
    _procesarFotosIniciales();
    if (mounted) {
      setState(() {
        _cargandoTiempos = false;
      });
    }
  }

  void _procesarFotosIniciales() {
    if (fotos.isNotEmpty) {
      fotos.sort((a, b) {
        int idA = int.tryParse(_limpiar(a['id'])) ?? 0;
        int idB = int.tryParse(_limpiar(b['id'])) ?? 0;
        return idB.compareTo(idA);
      });
    }

    String rawLat = _limpiar(
        fotos.isNotEmpty ? fotos[0]["latitud"] : widget.asignacion?["latitud"]);
    String rawLng = _limpiar(fotos.isNotEmpty
        ? fotos[0]["longitud"]
        : widget.asignacion?["longitud"]);

    double lat = double.tryParse(rawLat) ?? 0.0;
    double lng = double.tryParse(rawLng) ?? 0.0;
    _ubicacionInicial = LatLng(lat, lng);

    if (lat != 0) {
      _obtenerDireccionEscrita(lat.toString(), lng.toString());
    }

    _markers.clear();
    _markers.add(
        Marker(markerId: const MarkerId('punto'), position: _ubicacionInicial));
  }

  bool _puedeEliminar(dynamic createdAt) {
    if (widget.nivelId != 3 || createdAt == null) {
      return false;
    }
    try {
      DateTime fechaFoto = DateTime.parse(createdAt.toString());
      DateTime ahora = DateTime.now();
      return ahora.difference(fechaFoto).inMinutes < 5;
    } catch (e) {
      return false;
    }
  }

  Future<void> _eliminarFoto(dynamic fotoId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Eliminar fotografía?"),
        content: const Text("Esta acción borrará la imagen permanentemente."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ELIMINAR",
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() => _actualizando = true);
      try {
        final response = await http.post(
          Uri.parse("https://sistema.jusaimpulsemkt.com/api/eliminar-foto-app"),
          body: {"foto_id": fotoId.toString()},
        );
        if (response.statusCode == 200 && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("✅ Foto eliminada")));
          _refrescarGaleria();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("❌ Error de red")));
        }
      } finally {
        if (mounted) setState(() => _actualizando = false);
      }
    }
  }

  Future<void> _obtenerDireccionEscrita(String lat, String lng) async {
    try {
      final url = Uri.parse(
          "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_googleMapsApiKey&language=es");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["status"] == "OK" && mounted) {
          setState(() {
            _direccionEscrita = data["results"][0]["formatted_address"];
          });
        }
      }
    } catch (e) {
      debugPrint("Geocoding Error: $e");
    }
  }

  Future<void> _refrescarGaleria() async {
    if (_actualizando) return;
    setState(() => _actualizando = true);
    try {
      final idAsig = _limpiar(widget.asignacion?["id"]);
      final url = Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/fotos-asignacion-app/$idAsig");
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> nuevasFotos =
            decoded is Map ? (decoded['datos'] ?? []) : decoded;
        if (mounted) {
          setState(() {
            fotos = nuevasFotos;
            _procesarFotosIniciales();
          });
        }
      }
    } catch (e) {
      debugPrint("Refresh Error: $e");
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("FOTOS",
            style: TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF424949),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: _actualizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _refrescarGaleria,
          ),
        ],
      ),
      body: _cargandoTiempos
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildMapaSeccion()),
                if (fotos.isEmpty)
                  const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text("SIN FOTOS REGISTRADAS")))
                else
                  SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: _buildGridSliver()),
              ],
            ),
    );
  }

  Widget _buildMapaSeccion() {
    bool esWindows = Platform.isWindows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.grey[200],
          child: const Text("UBICACIÓN DEL REGISTRO",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        SizedBox(
          height: 220,
          child: esWindows
              ? Container(
                  color: Colors.grey[300],
                  child: const Center(
                      child: Text("Mapa no disponible en Windows")))
              : GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: _ubicacionInicial, zoom: 15.0),
                  markers: _markers,
                  onMapCreated: (c) {
                    if (!_controller.isCompleted) _controller.complete(c);
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_direccionEscrita,
                      style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildGridSliver() {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
      delegate: SliverChildBuilderDelegate((context, index) {
        final f = fotos[index];
        final bool puedeBorrar = _puedeEliminar(f["created_at"]);

        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                "${PhotoGalleryScreen.baseImageUrl}${_limpiar(f["foto"])}",
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
              ),
              if (puedeBorrar)
                Positioned(
                  top: 5,
                  right: 5,
                  child: GestureDetector(
                    onTap: () => _eliminarFoto(f["id"]),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        // ✅ CORRECCIÓN: Uso de .withValues en lugar de withOpacity
                        color: Colors.red.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_forever,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
            ],
          ),
        );
      }, childCount: fotos.length),
    );
  }
}//photo_gallery_screen.dart//