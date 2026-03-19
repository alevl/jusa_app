import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:convert';
// ✅ Se eliminó import 'dart:io'; porque no se está usando actualmente.

// Cambiamos el nombre de la clase a DashboardScreen para que coincida con tu navegación
class DashboardScreen extends StatefulWidget {
  final int userId; // Agregado para coincidir con el menú
  final String userName; // Agregado para coincidir con el menú
  final int? nivelId;
  final List<dynamic>? fotosServidor;
  final dynamic asignacion;

  // URL base para las imágenes del servidor
  static const String baseImageUrl =
      "https://sistema.jusaimpulsemkt.com/storage/";

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.fotosServidor,
    this.asignacion,
    this.nivelId,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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
    // Clonamos la lista para poder manipularla localmente
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

  bool _puedeEliminar() {
    final String nivelActual = _limpiar(widget.nivelId);
    return nivelActual == "3" && _segundosTranscurridos < 300;
  }

  // --- MÉTODOS DE UI Y API ---

  Future<void> _eliminarFoto(dynamic fotoId) async {
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

      if (response.statusCode == 405) {
        response = await http
            .get(Uri.parse(urlFinal))
            .timeout(const Duration(seconds: 15));
      }

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("✅ Foto eliminada"), backgroundColor: Colors.green),
        );
        _refrescarGaleria();
      }
    } catch (e) {
      debugPrint("Error al eliminar: $e");
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  Future<void> _refrescarGaleria() async {
    try {
      final idAsig = _limpiar(widget.asignacion?["id"]);
      if (idAsig.isEmpty) return;

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
            title: Text("DASHBOARD - ${widget.userName.toUpperCase()}",
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF424949),
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refrescarGaleria),
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
        ),
        if (_actualizando) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text("Procesando...",
                style: TextStyle(
                    color: Colors.white,
                    decoration: TextDecoration.none,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildMapaSeccion() {
    if (_limpiar(widget.nivelId) == "3") return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
            height: 200,
            child: GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: _ubicacionInicial, zoom: 15.0),
                markers: _markers,
                onMapCreated: (c) => _controller.complete(c))),
        ListTile(
          leading: const Icon(Icons.location_on, color: Colors.red),
          title: Text(_direccionEscrita, style: const TextStyle(fontSize: 11)),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildGridSliver() {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.75),
      delegate: SliverChildBuilderDelegate((context, index) {
        final f = fotos[index];
        final url = "${DashboardScreen.baseImageUrl}${_limpiar(f["foto"])}";
        return Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url,
                    fit: BoxFit.cover, width: double.infinity),
              ),
            ),
            if (_puedeEliminar())
              TextButton.icon(
                onPressed: () => _eliminarFoto(f["id"]),
                icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                label: const Text("Eliminar",
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              )
          ],
        );
      }, childCount: fotos.length),
    );
  }
}
