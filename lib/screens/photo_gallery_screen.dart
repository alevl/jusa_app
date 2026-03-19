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

  // URL base para las imágenes del servidor
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

  int _segundosTranscurridos = 0;
  Timer? _timerPermanencia;

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  late LatLng _ubicacionInicial = const LatLng(0, 0);
  final Set<Marker> _markers = {};

  // Tu API Key de Google Maps
  final String _googleMapsApiKey = "AIzaSyC-aarw02OP9iW4pwHoOlbZ2njidcJY82I";

  @override
  void initState() {
    super.initState();
    // Clonamos la lista para poder manipularla localmente (borrar fotos de la UI)
    fotos =
        widget.fotosServidor != null ? List.from(widget.fotosServidor!) : [];
    _inicializarPantalla();
    _iniciarContadorPermanencia();
  }

  @override
  void dispose() {
    _timerPermanencia?.cancel();
    super.dispose();
  }

  void _iniciarContadorPermanencia() {
    _timerPermanencia = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _segundosTranscurridos++;
        });
        // Límite de 5 minutos (300 segundos) para borrar fotos
        if (_segundosTranscurridos >= 300) {
          timer.cancel();
        }
      }
    });
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
    // Ordenar fotos por ID descendente
    if (fotos.isNotEmpty) {
      fotos.sort((a, b) {
        int idA = int.tryParse(_limpiar(a['id'])) ?? 0;
        int idB = int.tryParse(_limpiar(b['id'])) ?? 0;
        return idB.compareTo(idA);
      });
    }

    // Ubicación basada en la primera foto o en la asignación
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

  bool _puedeEliminar() {
    final String nivelActual = _limpiar(widget.nivelId);
    // Solo nivel 3 y antes de los 5 minutos
    return nivelActual == "3" && _segundosTranscurridos < 300;
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
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                        child: CircularProgressIndicator(color: Colors.white));
                  },
                ),
              ),
            ),
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

  Future<void> _eliminarFoto(dynamic fotoId) async {
    // ✅ CORRECCIÓN: Usamos 'confirmar' para validar el flujo y limpiar el linter
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

    if (confirmar != true) return;

    setState(() => _actualizando = true);
    try {
      final String idLimpio = _limpiar(fotoId);
      final String urlFinal =
          "https://sistema.jusaimpulsemkt.com/api/eliminar-foto-app/$idLimpio";

      var response = await http
          .delete(Uri.parse(urlFinal))
          .timeout(const Duration(seconds: 15));

      // Fallback si el servidor requiere GET para eliminar (común en algunos hostings)
      if (response.statusCode == 405) {
        response = await http
            .get(Uri.parse(urlFinal))
            .timeout(const Duration(seconds: 15));
      }

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("✅ Foto eliminada correctamente"),
              backgroundColor: Colors.green),
        );
        setState(() {
          fotos.removeWhere((item) => _limpiar(item['id']) == idLimpio);
        });
        await _refrescarGaleria();
      } else if (mounted) {
        _mostrarErrorServidor(response.statusCode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("❌ Error de red al intentar eliminar")));
      }
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  void _mostrarErrorServidor(int code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Error $code"),
        content: const Text("El servidor no pudo procesar la eliminación."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CERRAR"))
        ],
      ),
    );
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
            _procesarFotosIniciales();
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
                icon: const Icon(Icons.refresh),
                onPressed: _refrescarGaleria,
              ),
            ],
          ),
          body: _cargandoTiempos
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildMapaSeccion()),
                    if (fotos.isEmpty) ...[
                      const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text("SIN FOTOS REGISTRADAS")))
                    ] else ...[
                      SliverPadding(
                          padding: const EdgeInsets.all(12),
                          sliver: _buildGridSliver()),
                    ],
                  ],
                ),
        ),
        // Pantalla de carga bloqueante optimizada con const
        if (_actualizando)
          Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF424949)),
                  SizedBox(height: 25),
                  Text("Eliminando fotografía...",
                      style: TextStyle(
                          color: Color(0xFF424949),
                          decoration: TextDecoration.none,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  Text("Por favor espere.",
                      style: TextStyle(
                          color: Colors.grey,
                          decoration: TextDecoration.none,
                          fontSize: 12,
                          fontWeight: FontWeight.normal)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapaSeccion() {
    final String nivelActual = _limpiar(widget.nivelId);
    // Si es nivel 3, no mostramos el mapa (según tu lógica previa)
    if (nivelActual == "3") return const SizedBox.shrink();

    bool esWindows = Platform.isWindows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey[200],
            child: const Text("UBICACIÓN DEL REGISTRO",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        SizedBox(
            height: 220,
            child: esWindows
                ? Container(
                    color: Colors.grey[300],
                    child: const Center(child: Text("Mapa no disponible")))
                : GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: _ubicacionInicial, zoom: 15.0),
                    markers: _markers,
                    onMapCreated: (c) {
                      if (!_controller.isCompleted) {
                        _controller.complete(c);
                      }
                    })),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.location_on, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_direccionEscrita,
                      style: const TextStyle(fontSize: 12)))
            ])),
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
          childAspectRatio: 0.70),
      delegate: SliverChildBuilderDelegate((context, index) {
        final f = fotos[index];
        final url = "${PhotoGalleryScreen.baseImageUrl}${_limpiar(f["foto"])}";
        final bool puedeBorrar = _puedeEliminar();

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
                    height: double.infinity,
                    errorBuilder: (c, e, s) => Container(
                      color: Colors.grey[100],
                      child: const Icon(Icons.broken_image,
                          color: Colors.grey, size: 30),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              height: 50,
              padding: const EdgeInsets.only(top: 8.0),
              child: puedeBorrar
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _eliminarFoto(f["id"]),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text("ELIMINAR",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      }, childCount: fotos.length),
    );
  }
}
