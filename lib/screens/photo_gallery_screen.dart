import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:convert';

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
  final Map<String, int> _tiemposFotos = {};
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
    if (valor == null) {
      return "";
    }
    return valor.toString().trim().replaceAll(RegExp(r'[\n\r\t]'), '');
  }

  void _inicializarPantalla() {
    try {
      _procesarFotosIniciales();
      _inicializarPersistencia();
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargandoTiempos = false;
        });
      }
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

    if (_controller.isCompleted) {
      _controller.future.then((c) {
        c.animateCamera(CameraUpdate.newLatLng(_ubicacionInicial));
      });
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
      debugPrint(e.toString());
    }
  }

  Future<void> _inicializarPersistencia() async {
    final prefs = await SharedPreferences.getInstance();
    final ahora = DateTime.now().millisecondsSinceEpoch;
    for (var f in fotos) {
      String id = _limpiar(f['id']);
      if (id.isEmpty) {
        continue;
      }
      String key = "ts_foto_$id";
      if (!prefs.containsKey(key)) {
        await prefs.setInt(key, ahora);
      }
      _tiemposFotos[id] = prefs.getInt(key) ?? ahora;
    }
    if (mounted) {
      setState(() {
        _cargandoTiempos = false;
      });
    }
  }

  Future<void> _refrescarGaleria() async {
    if (_actualizando) {
      return;
    }
    setState(() {
      _actualizando = true;
    });
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
      debugPrint(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _actualizando = false;
        });
      }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.grey[200],
          child: const Text("UBICACIÓN DEL CHOFER",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        SizedBox(
          height: 220,
          child: GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _ubicacionInicial, zoom: 15.0),
            markers: _markers,
            onMapCreated: (c) {
              if (!_controller.isCompleted) {
                _controller.complete(c);
              }
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
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Image.network(
              "${PhotoGalleryScreen.baseImageUrl}${_limpiar(f["foto"])}",
              fit: BoxFit.cover, errorBuilder: (c, e, s) {
            return const Icon(Icons.broken_image);
          }),
        );
      }, childCount: fotos.length),
    );
  }
}
