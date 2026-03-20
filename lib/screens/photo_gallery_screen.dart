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

  Timer? _timerRefresco;

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
    _iniciarTimerRefresco();
  }

  @override
  void dispose() {
    _timerRefresco?.cancel();
    super.dispose();
  }

  void _iniciarTimerRefresco() {
    _timerRefresco = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String _limpiar(dynamic valor) {
    if (valor == null) {
      return "";
    }
    return valor.toString().trim().replaceAll(RegExp(r'[\n\r\t]'), '');
  }

  bool _puedeEliminarFotoIndividual(dynamic foto) {
    final String nivelStr = _limpiar(widget.nivelId);
    final int nivelActual = int.tryParse(nivelStr) ?? 0;

    // Nivel 5 (Asistente) siempre tiene permiso
    if (nivelActual == 5) {
      return true;
    }

    // Nivel 3 (Chofer) validación de tiempo
    if (nivelActual == 3) {
      try {
        // Intentamos obtener la fecha de created_at o combinando fecha y hora
        String? rawFecha =
            foto["created_at"] ?? "${foto["fecha"]} ${foto["hora"]}";

        if (rawFecha == null || rawFecha.contains("null")) {
          return false;
        }

        // Normalizamos el formato: reemplazamos "/" por "-" para que DateTime lo entienda
        String fechaNormalizada = rawFecha.replaceAll('/', '-');

        DateTime horaFoto = DateTime.parse(fechaNormalizada);
        DateTime ahora = DateTime.now();

        int diferencia = ahora.difference(horaFoto).inSeconds;

        // Debug para consola: Así verás por qué no aparece si falla el tiempo
        // print("ID: ${foto['id']} - Diferencia: $diferencia seg");

        return diferencia >= 0 && diferencia < 300;
      } catch (e) {
        debugPrint("Error crítico de fecha: $e");
        return false;
      }
    }

    return false;
  }

  bool _puedeTomarFoto() {
    return _limpiar(widget.nivelId) == "3";
  }

  void _inicializarPantalla() {
    _procesarFotosYMarcadores();
    if (mounted) {
      setState(() {
        _cargandoTiempos = false;
      });
    }
  }

  void _procesarFotosYMarcadores() {
    _markers.clear();
    if (fotos.isNotEmpty) {
      fotos.sort((a, b) {
        int idA = int.tryParse(_limpiar(a['id'])) ?? 0;
        int idB = int.tryParse(_limpiar(b['id'])) ?? 0;
        return idB.compareTo(idA);
      });

      for (var f in fotos) {
        double? lat = double.tryParse(_limpiar(f["latitud"]));
        double? lng = double.tryParse(_limpiar(f["longitud"]));

        if (lat != null && lng != null && lat != 0) {
          if (_markers.isEmpty) {
            _ubicacionInicial = LatLng(lat, lng);
            _obtenerDireccionEscrita(lat.toString(), lng.toString());
          }
          _markers.add(
            Marker(
              markerId: MarkerId('foto_${f["id"]}'),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(
                title: "Foto ID: ${f["id"]}",
                snippet: "Hora: ${f["hora"] ?? 'No registrada'}",
              ),
            ),
          );
        }
      }
    }

    if (_markers.isEmpty) {
      double latAsig =
          double.tryParse(_limpiar(widget.asignacion?["latitud"])) ?? 0.0;
      double lngAsig =
          double.tryParse(_limpiar(widget.asignacion?["longitud"])) ?? 0.0;
      _ubicacionInicial = LatLng(latAsig, lngAsig);
      if (latAsig != 0) {
        _markers.add(Marker(
            markerId: const MarkerId('punto_base'),
            position: _ubicacionInicial));
      }
    }
  }

  Future<void> _ajustarCamaraATodosLosPuntos() async {
    if (_markers.isEmpty) {
      return;
    }
    final GoogleMapController controller = await _controller.future;

    double minLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLat = _markers.first.position.latitude;
    double maxLng = _markers.first.position.longitude;

    for (Marker m in _markers) {
      if (m.position.latitude < minLat) {
        minLat = m.position.latitude;
      }
      if (m.position.latitude > maxLat) {
        maxLat = m.position.latitude;
      }
      if (m.position.longitude < minLng) {
        minLng = m.position.longitude;
      }
      if (m.position.longitude > maxLng) {
        maxLng = m.position.longitude;
      }
    }

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng)),
        70.0,
      ),
    );
  }

  void _verFotoGrande(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
                child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain))),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _eliminarFoto(dynamic foto) async {
    if (!_puedeEliminarFotoIndividual(foto)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❌ El tiempo para eliminar esta foto ha expirado."),
            backgroundColor: Colors.red),
      );
      return;
    }

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Eliminar fotografía?"),
        content: const Text("Esta acción borrará la imagen permanentemente."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("CANCELAR")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ELIMINAR",
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    setState(() => _actualizando = true);
    try {
      final String idLimpio = _limpiar(foto["id"]);
      final String urlFinal =
          "https://sistema.jusaimpulsemkt.com/api/eliminar-foto-app/$idLimpio";
      var response = await http
          .delete(Uri.parse(urlFinal))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("✅ Foto eliminada"), backgroundColor: Colors.green),
        );
        setState(() {
          fotos.removeWhere((item) => _limpiar(item['id']) == idLimpio);
          _procesarFotosYMarcadores();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("❌ Error de red")));
      }
    } finally {
      if (mounted) {
        setState(() => _actualizando = false);
      }
    }
  }

  Future<void> _refrescarGaleria() async {
    try {
      final idAsig = _limpiar(widget.asignacion?["id"]);
      final response = await http.get(Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/fotos-asignacion-app/$idAsig"));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> nuevasFotos =
            decoded is Map ? (decoded['datos'] ?? []) : decoded;
        if (mounted) {
          setState(() {
            fotos = nuevasFotos;
            _procesarFotosYMarcadores();
          });
          Future.delayed(const Duration(milliseconds: 300), () {
            _ajustarCamaraATodosLosPuntos();
          });
        }
      }
    } catch (e) {
      debugPrint("Error refrescando: $e");
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text("REPORTE FOTOGRÁFICO",
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF424949),
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refrescarGaleria,
              )
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
          floatingActionButton: _puedeTomarFoto()
              ? FloatingActionButton(
                  onPressed: () {
                    Navigator.pop(context, "take_photo");
                  },
                  backgroundColor: const Color(0xFF424949),
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                )
              : null,
        ),
        if (_actualizando)
          Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF424949)),
                  SizedBox(height: 20),
                  Text("Actualizando información...",
                      style: TextStyle(
                          color: Color(0xFF424949),
                          decoration: TextDecoration.none,
                          fontSize: 14)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapaSeccion() {
    final int nivelActual = int.tryParse(_limpiar(widget.nivelId)) ?? 0;

    // Mapa habilitado para 2, 4 y 5. Oculto para 3 (Chofer).
    if (nivelActual == 3) {
      return const SizedBox.shrink();
    }

    bool esWindows = Platform.isWindows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: const Color(0xFFF5F5F5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("PUNTOS DE CAPTURA",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Color(0xFF808080))),
              GestureDetector(
                onTap: _ajustarCamaraATodosLosPuntos,
                child: const Row(
                  children: [
                    Icon(Icons.zoom_out_map, size: 16, color: Colors.blue),
                    SizedBox(width: 4),
                    Text("Ver todos",
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: esWindows
              ? Container(
                  color: const Color(0xFFE0E0E0),
                  child: const Center(child: Text("Mapa no disponible")))
              : GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: _ubicacionInicial, zoom: 14.0),
                  markers: _markers,
                  myLocationButtonEnabled: true,
                  onMapCreated: (c) {
                    if (!_controller.isCompleted) {
                      _controller.complete(c);
                    }
                    Future.delayed(const Duration(milliseconds: 600), () {
                      _ajustarCamaraATodosLosPuntos();
                    });
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_direccionEscrita,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF212121)))),
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
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final f = fotos[index];
        final url = "${PhotoGalleryScreen.baseImageUrl}${_limpiar(f["foto"])}";

        final bool puedeBorrar = _puedeEliminarFotoIndividual(f);

        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _verFotoGrande(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (c, e, s) => Container(
                        color: const Color(0xFFF5F5F5),
                        child:
                            const Icon(Icons.broken_image, color: Colors.grey)),
                  ),
                ),
              ),
            ),
            if (puedeBorrar)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 35,
                  child: ElevatedButton(
                    onPressed: () => _eliminarFoto(f),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text("ELIMINAR",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
                ),
              ),
          ],
        );
      }, childCount: fotos.length),
    );
  }
}
