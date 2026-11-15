import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// 1. PUNTO DE ENTRADA Y CONFIGURACION GLOBAL DE LA APP
void main() {
  runApp(const EkXplorationApp());
}

class EkXplorationApp extends StatelessWidget {
  const EkXplorationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FARM-EK',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Marca.fondo, // Fondo general (blanco azulado)
        colorScheme: ColorScheme.fromSeed(
          seedColor: Marca.neonBlue,
          primary: Marca.neonBlue,
          secondary: Marca.blueYonder,
          error: Marca.rocketRed,
        ),
        // Overpass para el texto normal (guía de marca: "Body Copy")
        fontFamily: GoogleFonts.overpass().fontFamily,
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: Marca.neonBlue),
        snackBarTheme: const SnackBarThemeData(backgroundColor: Marca.deepBlue),
        textSelectionTheme: const TextSelectionThemeData(cursorColor: Marca.neonBlue),
      ),
      home: const WelcomeScreen(), // Pantalla inicial con la que arranca la app
    );
  }
}

// ============================================================
// 1.0 IDENTIDAD VISUAL: PALETA NASA SPACE APPS, DEGRADADO, PATRONES Y FUENTES
// ============================================================
class Marca {
  // Paleta oficial
  static const blueYonder = Color(0xFF2E96F5);
  static const neonBlue = Color(0xFF0960E1);
  static const electricBlue = Color(0xFF0042A6);
  static const deepBlue = Color(0xFF07173F);
  static const rocketRed = Color(0xFFE43700);
  static const martianRed = Color(0xFF8E1100);
  static const neonYellow = Color(0xFFEAFE07);
  static const white = Color(0xFFFFFFFF);

  // Tonos de apoyo (derivados de la paleta, para fondos y bordes claros)
  static const fondo = Color(0xFFF4F7FC);
  static const azulSuave = Color(0xFFEAF1FD);
  static const azulSeleccion = Color(0xFFD6E4FB);
  static const borde = Color(0xFFDCE4F2);
  static const rojoSuave = Color(0xFFFDECE6);
  static const rojoBorde = Color(0xFFF6B9A3);

  // Degradado oficial: Electric Blue -> Deep Blue a 45°
  static const degradado = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [electricBlue, deepBlue],
  );

  // Fira Sans para títulos (guía de marca: "Titles & Headings")
  static TextStyle titulo({double size = 26, Color color = deepBlue, FontWeight peso = FontWeight.w800}) =>
      GoogleFonts.firaSans(fontSize: size, fontWeight: peso, color: color, letterSpacing: -0.3);
}

// Fondo de marca: degradado azul + patrones a ~25 % de opacidad
class FondoMarca extends StatelessWidget {
  final Widget? child;
  final BorderRadius? borderRadius;
  final int variante; // Cambia la posición de los patrones

  const FondoMarca({super.key, this.child, this.borderRadius, this.variante = 0});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Marca.degradado),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: PatronEspacialPainter(variante: variante))),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

// Patrones de la marca: órbitas, coordenadas (cruces) y curvas de nivel
class PatronEspacialPainter extends CustomPainter {
  final int variante;
  const PatronEspacialPainter({this.variante = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final linea = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Órbitas: elipses concéntricas que salen desde una esquina
    final centroOrbita = variante.isEven ? Offset(w * 1.02, h * -0.05) : Offset(w * -0.05, h * 1.05);
    final base = math.max(w, h);
    for (final f in [0.25, 0.42, 0.62, 0.85]) {
      canvas.drawOval(Rect.fromCenter(center: centroOrbita, width: base * f * 1.4, height: base * f), linea);
    }

    // Curvas de nivel (ondas suaves)
    for (int i = 0; i < 3; i++) {
      final y = h * (0.55 + i * 0.14);
      final curva = Path()
        ..moveTo(0, y)
        ..cubicTo(w * 0.3, y - h * 0.18, w * 0.6, y + h * 0.16, w, y - h * 0.06);
      canvas.drawPath(curva, linea);
    }

    // Coordenadas: pequeñas cruces en posiciones fijas
    final azar = math.Random(7 + variante);
    final cruz = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final cantidad = (w * h / 22000).clamp(6, 40).round();
    for (int i = 0; i < cantidad; i++) {
      final c = Offset(azar.nextDouble() * w, azar.nextDouble() * h);
      final t = 3 + azar.nextDouble() * 4;
      canvas.drawLine(c - Offset(t, 0), c + Offset(t, 0), cruz);
      canvas.drawLine(c - Offset(0, t), c + Offset(0, t), cruz);
    }
  }

  @override
  bool shouldRepaint(covariant PatronEspacialPainter old) => old.variante != variante;
}

// ============================================================
// 1.1 MODELO DE DATOS: PROYECTO
// Cada proyecto se convierte a JSON (toJson) para guardarlo
// y se reconstruye desde JSON (fromJson) al cargarlo.
// ============================================================
class Proyecto {
  final String id;
  final String nombre;
  final double latitud;
  final double longitud;
  final double ancho;
  final double largo;
  final double profundidad;
  final double humedad;
  final double ph;
  final double materiaOrganica;
  final DateTime fechaCreacion;

  const Proyecto({
    required this.id,
    required this.nombre,
    required this.latitud,
    required this.longitud,
    required this.ancho,
    required this.largo,
    required this.profundidad,
    required this.humedad,
    required this.ph,
    required this.materiaOrganica,
    required this.fechaCreacion,
  });

  // Copia del proyecto cambiando solo los datos de suelo que llegan de la API
  Proyecto conSuelo({required double humedad, required double ph, required double materiaOrganica}) => Proyecto(
        id: id,
        nombre: nombre,
        latitud: latitud,
        longitud: longitud,
        ancho: ancho,
        largo: largo,
        profundidad: profundidad,
        humedad: humedad,
        ph: ph,
        materiaOrganica: materiaOrganica,
        fechaCreacion: fechaCreacion,
      );

  // Superficie del terreno en m²
  double get superficie => ancho * largo;

  // Convierte el proyecto a un Map listo para jsonEncode
  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'latitud': latitud,
        'longitud': longitud,
        'ancho': ancho,
        'largo': largo,
        'profundidad': profundidad,
        'humedad': humedad,
        'ph': ph,
        'materiaOrganica': materiaOrganica,
        'fechaCreacion': fechaCreacion.toIso8601String(),
      };

  // Reconstruye un proyecto a partir de un Map que vino de jsonDecode
  factory Proyecto.fromJson(Map<String, dynamic> json) {
    double numero(String clave) => (json[clave] as num?)?.toDouble() ?? 0;

    return Proyecto(
      id: json['id'] as String,
      nombre: json['nombre'] as String? ?? 'Sin nombre',
      latitud: numero('latitud'),
      longitud: numero('longitud'),
      ancho: numero('ancho'),
      largo: numero('largo'),
      profundidad: numero('profundidad'),
      humedad: numero('humedad'),
      ph: numero('ph'),
      materiaOrganica: numero('materiaOrganica'),
      fechaCreacion: DateTime.tryParse(json['fechaCreacion'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

// ============================================================
// 1.2 ALMACENAMIENTO: ARCHIVO proyectos.json EN LA CARPETA DEL SERVIDOR
// Los proyectos viven en el archivo proyectos.json (no en la memoria del navegador).
// ============================================================
// Archivo donde se guardan los proyectos.
// - App de Windows: el main.dart lo escribe DIRECTAMENTE aquí.
// - App web: el navegador no puede escribir en tu disco, así que lo escribe el
//   servidor de Python en esta misma ruta (CARPETA_PROYECTOS en servidor_clima.py).
const String kArchivoProyectos = r'C:\Users\tblbe\ek_xploration\lib\proyectos.json';

class ProyectoStorage {
  // En Windows (o cualquier app que no sea web) se usa el archivo directamente
  static bool get _usarArchivo => !kIsWeb;
  static File get _archivo => File(kArchivoProyectos);

  static Future<List<Map<String, dynamic>>> _leerArchivo() async {
    if (!await _archivo.exists()) return [];
    final texto = await _archivo.readAsString();
    if (texto.trim().isEmpty) return [];
    return (jsonDecode(texto) as List<dynamic>).cast<Map<String, dynamic>>();
  }

  static Future<void> _escribirArchivo(List<Map<String, dynamic>> proyectos) async {
    await _archivo.parent.create(recursive: true); // Crea la carpeta si no existe
    const formato = JsonEncoder.withIndent('  ');
    await _archivo.writeAsString(formato.convert(proyectos), flush: true);
  }

  // Antes los proyectos se guardaban dentro del navegador con esta clave.
  // Se usa solo para pasarlos una vez al archivo proyectos.json del servidor.
  static const _claveNavegador = 'farmek_proyectos';

  static Uri _url([String? id]) =>
      Uri.parse(id == null ? '$kServidorClima/api/proyectos' : '$kServidorClima/api/proyectos/${Uri.encodeComponent(id)}');

  static Never _sinServidor() =>
      throw Exception('No se pudo conectar con el servidor. ¿Está corriendo servidor_clima.py?');

  // Lee todos los proyectos del archivo proyectos.json (el más reciente primero)
  static Future<List<Proyecto>> cargarTodos() async {
    await _migrarDelNavegador();

    if (_usarArchivo) {
      final proyectos = (await _leerArchivo()).map(Proyecto.fromJson).toList();
      proyectos.sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));
      return proyectos;
    }

    final http.Response respuesta;
    try {
      respuesta = await http.get(_url()).timeout(const Duration(seconds: 15));
    } catch (_) {
      _sinServidor();
    }
    if (respuesta.statusCode != 200) {
      throw Exception('El servidor respondió con error ${respuesta.statusCode}');
    }

    final json = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final proyectos = (json['proyectos'] as List<dynamic>)
        .map((e) => Proyecto.fromJson(e as Map<String, dynamic>))
        .toList();
    proyectos.sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));
    return proyectos;
  }

  // Crea el proyecto o reemplaza el que tenga el mismo id
  static Future<void> guardar(Proyecto proyecto) async {
    if (_usarArchivo) {
      final proyectos = await _leerArchivo();
      proyectos.removeWhere((p) => p['id'] == proyecto.id);
      proyectos.add(proyecto.toJson());
      await _escribirArchivo(proyectos);
      return;
    }

    final http.Response respuesta;
    try {
      respuesta = await http
          .put(
            _url(proyecto.id),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(proyecto.toJson()),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      _sinServidor();
    }
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo guardar el proyecto (error ${respuesta.statusCode})');
    }
  }

  // Elimina un proyecto por su id
  static Future<void> eliminar(String id) async {
    if (_usarArchivo) {
      final proyectos = await _leerArchivo();
      proyectos.removeWhere((p) => p['id'] == id);
      await _escribirArchivo(proyectos);
      return;
    }

    final http.Response respuesta;
    try {
      respuesta = await http.delete(_url(id)).timeout(const Duration(seconds: 15));
    } catch (_) {
      _sinServidor();
    }
    if (respuesta.statusCode != 200 && respuesta.statusCode != 404) {
      throw Exception('No se pudo eliminar el proyecto (error ${respuesta.statusCode})');
    }
  }

  // Si quedaron proyectos guardados en este navegador (versión anterior),
  // se suben una sola vez a proyectos.json y se borran del navegador.
  static Future<void> _migrarDelNavegador() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_claveNavegador);
      if (texto == null || texto.isEmpty) return;

      final lista = jsonDecode(texto) as List<dynamic>;
      for (final e in lista) {
        await guardar(Proyecto.fromJson(e as Map<String, dynamic>));
      }
      await prefs.remove(_claveNavegador);
    } catch (_) {
      // Si algo falla (por ejemplo, el servidor está apagado), se intenta la próxima vez
    }
  }
}

// Función auxiliar: abre la lista de proyectos guardados y, si el usuario
// elige uno, entra al Dashboard con ese proyecto.
Future<void> abrirProyectoGuardado(BuildContext context) async {
  final proyecto = await showDialog<Proyecto>(
    context: context,
    builder: (context) => const LoadProjectDialog(),
  );

  if (!context.mounted || proyecto == null) return;

  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (context) => DashboardScreen(proyecto: proyecto)),
  );
}

//2. PANTALLA DE BIENVENIDA (Welcome Screen)

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 2.1 Fondo de marca: degradado azul + patrones
          const Positioned.fill(child: FondoMarca()),

          // Círculos concéntricos decorativos (órbitas) sobre el degradado
          Center(
            child: CustomPaint(
              painter: ConcentricCirclesPainter(),
              size: const Size(double.infinity, double.infinity),
            ),
          ),

          // 2.2 Contenido central (Logo, Títulos y Botones de acción)
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo central con icono de hoja y borde circular
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                      ),
                      child: const Icon(Icons.eco, size: 48, color: Marca.white),
                    ),
                    const SizedBox(height: 16),
                    Text('FARM-EK', style: Marca.titulo(size: 38, color: Marca.white, peso: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text(
                      'SIEMBRA  •  PREDICE  •  COSECHA',
                      style: TextStyle(color: Marca.blueYonder, fontSize: 13, letterSpacing: 2.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 40),

                    // Botón principal: New Project (abre formulario, guarda y navega al Dashboard)
                    SizedBox(
                      width: 280,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Marca.neonYellow, // Neon Yellow: solo para la acción principal
                          foregroundColor: Marca.deepBlue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          // Abre el formulario para registrar una nueva parcela.
                          final nuevoProyecto = await showDialog<Proyecto>(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const NewProjectDialog(),
                          );

                          if (nuevoProyecto == null) return;

                          // Guarda el proyecto en proyectos.json (a través del servidor)
                          try {
                            await ProyectoStorage.guardar(nuevoProyecto);
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                            );
                            return;
                          }

                          if (!context.mounted) return;

                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DashboardScreen(proyecto: nuevoProyecto),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Icon(Icons.add, size: 18),
                            Text('New project', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            Icon(Icons.arrow_outward, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Botón secundario: Load file (muestra los proyectos guardados)
                    SizedBox(
                      width: 280,
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Marca.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => abrirProyectoGuardado(context),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: const [
                            Icon(Icons.folder_open_outlined, size: 18, color: Marca.white),
                            SizedBox(width: 16),
                            Text('Load file', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Marca.white)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Cada gran cosecha comienza bajo la superficie.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 2.3 Textos decorativos ubicados en las esquinas de la pantalla
          //     (se ocultan en ventanas angostas para que no se encimen)
          if (MediaQuery.sizeOf(context).width >= 640) ...[
            const Positioned(top: 24, left: 24, child: Text('• AGRICULTURA CON CIENCIA', style: TextStyle(fontSize: 11, color: Marca.neonYellow, fontWeight: FontWeight.w700, letterSpacing: 1))),
            const Positioned(top: 24, right: 24, child: Text('EXPLORATION LAB / 01', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600, letterSpacing: 1))),
            const Positioned(bottom: 24, left: 24, child: Text('Comprende tu suelo. Cultiva posibilidades.', style: TextStyle(fontSize: 11, color: Colors.white70))),
            const Positioned(bottom: 24, right: 24, child: Text('+  FARM-EK / v.1.0', style: TextStyle(fontSize: 11, color: Colors.white70))),
          ],
        ],
      ),
    );
  }
}


// 2.4 FORMULARIO PARA CREAR (O EDITAR) UN PROYECTO
// Si recibe un proyecto, se abre en modo "Configurar terreno" con sus valores.
class NewProjectDialog extends StatefulWidget {
  final Proyecto? proyectoInicial;

  const NewProjectDialog({super.key, this.proyectoInicial});

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _formKey = GlobalKey<FormState>();

  // Indica si se está buscando la ubicación
  bool _obteniendoUbicacion = false;

  final _nombreController = TextEditingController(text: 'Parcela experimental');
  final _latitudController = TextEditingController();
  final _longitudController = TextEditingController();
  final _anchoController = TextEditingController(text: '50');
  final _largoController = TextEditingController(text: '30');
  final _profundidadController = TextEditingController(text: '1');
  final _humedadController = TextEditingController(text: '24.8');
  final _phController = TextEditingController(text: '6.5');
  final _materiaOrganicaController = TextEditingController(text: '3.2');

  bool get _editando => widget.proyectoInicial != null;

  @override
  void initState() {
    super.initState();

    // Si estamos editando, llenamos el formulario con los valores guardados
    final p = widget.proyectoInicial;
    if (p != null) {
      String texto(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

      _nombreController.text = p.nombre;
      _latitudController.text = p.latitud.toString();
      _longitudController.text = p.longitud.toString();
      _anchoController.text = texto(p.ancho);
      _largoController.text = texto(p.largo);
      _profundidadController.text = texto(p.profundidad);
      _humedadController.text = texto(p.humedad);
      _phController.text = texto(p.ph);
      _materiaOrganicaController.text = texto(p.materiaOrganica);
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _latitudController.dispose();
    _longitudController.dispose();
    _anchoController.dispose();
    _largoController.dispose();
    _profundidadController.dispose();
    _humedadController.dispose();
    _phController.dispose();
    _materiaOrganicaController.dispose();
    super.dispose();
  }

  String? _validarTexto(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Este campo es obligatorio';
    }
    return null;
  }

  String? _validarNumero(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obligatorio';
    }
    if (double.tryParse(value.trim()) == null) {
      return 'Introduce un número válido';
    }
    return null;
  }

  Future<void> _obtenerUbicacion() async {
    if (_obteniendoUbicacion) return;

    setState(() {
      _obteniendoUbicacion = true;
    });

    try {
      late final Position posicion;

      if (kIsWeb) {
        // En navegador: aceptar una posición guardada de hasta 2 minutos
        // y limitar la espera para evitar que el botón quede cargando.
        posicion = await Geolocator.getCurrentPosition(
          locationSettings: WebSettings(
            accuracy: LocationAccuracy.low,
            maximumAge: const Duration(minutes: 2),
            timeLimit: const Duration(seconds: 15),
          ),
        );
      } else {
        // En escritorio/móvil: comprobar servicio y permisos del sistema.
        final servicioActivado = await Geolocator.isLocationServiceEnabled();

        if (!servicioActivado) {
          throw Exception('Activa los servicios de ubicación del dispositivo.');
        }

        LocationPermission permiso = await Geolocator.checkPermission();

        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission();
        }

        if (permiso == LocationPermission.denied ||
            permiso == LocationPermission.deniedForever) {
          throw Exception('No se concedió el permiso de ubicación.');
        }

        posicion = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
      }

      if (!mounted) return;

      // Escribir las coordenadas obtenidas en el formulario.
      _latitudController.text = posicion.latitude.toStringAsFixed(6);
      _longitudController.text = posicion.longitude.toStringAsFixed(6);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación obtenida correctamente.'),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo obtener la ubicación en 15 segundos. Comprueba el permiso del navegador e inténtalo de nuevo.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo obtener la ubicación: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _obteniendoUbicacion = false;
        });
      }
    }
  }

  Widget _campo({
    required String etiqueta,
    required TextEditingController controller,
    String? sufijo,
    bool numerico = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: numerico
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      validator: numerico ? _validarNumero : _validarTexto,
      decoration: InputDecoration(
        labelText: etiqueta,
        suffixText: sufijo,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _filaDosCampos(Widget primero, Widget segundo) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: primero),
        const SizedBox(width: 16),
        Expanded(child: segundo),
      ],
    );
  }

  // Valida el formulario y devuelve un objeto Proyecto al cerrar el diálogo
  void _crearProyecto() {
    if (!_formKey.currentState!.validate()) return;

    double leer(TextEditingController c) => double.parse(c.text.trim());

    final proyecto = Proyecto(
      // Al editar se conserva el mismo id para reemplazar el proyecto guardado
      id: widget.proyectoInicial?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nombre: _nombreController.text.trim(),
      latitud: leer(_latitudController),
      longitud: leer(_longitudController),
      ancho: leer(_anchoController),
      largo: leer(_largoController),
      profundidad: leer(_profundidadController),
      humedad: leer(_humedadController),
      ph: leer(_phController),
      materiaOrganica: leer(_materiaOrganicaController),
      fechaCreacion: widget.proyectoInicial?.fechaCreacion ?? DateTime.now(),
    );

    Navigator.of(context).pop(proyecto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        _editando ? 'Configurar terreno' : 'Nuevo proyecto',
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 590,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _campo(
                  etiqueta: 'Nombre del proyecto',
                  controller: _nombreController,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _obteniendoUbicacion ? null : _obtenerUbicacion,
                      icon: _obteniendoUbicacion
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.near_me_outlined, size: 17),
                      label: Text(
                        _obteniendoUbicacion ? 'Buscando...' : 'Localízame',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Marca.deepBlue,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Usa tu ubicación actual para llenar latitud y longitud.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _filaDosCampos(
                  _campo(
                    etiqueta: 'Latitud',
                    controller: _latitudController,
                    numerico: true,
                  ),
                  _campo(
                    etiqueta: 'Longitud',
                    controller: _longitudController,
                    numerico: true,
                  ),
                ),
                const SizedBox(height: 5),
                _filaDosCampos(
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Negativo = Sur', style: TextStyle(color: Colors.black54, fontSize: 12)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Negativo = Oeste', style: TextStyle(color: Colors.black54, fontSize: 12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _filaDosCampos(
                  _campo(etiqueta: 'Ancho del terreno', controller: _anchoController, sufijo: 'm', numerico: true),
                  _campo(etiqueta: 'Largo del terreno', controller: _largoController, sufijo: 'm', numerico: true),
                ),
                const SizedBox(height: 12),
                _filaDosCampos(
                  _campo(etiqueta: 'Profundidad del perfil', controller: _profundidadController, sufijo: 'm', numerico: true),
                  _campo(etiqueta: 'Humedad del suelo', controller: _humedadController, sufijo: '%', numerico: true),
                ),
                const SizedBox(height: 12),
                _filaDosCampos(
                  _campo(etiqueta: 'pH del suelo', controller: _phController, numerico: true),
                  _campo(etiqueta: 'Materia orgánica', controller: _materiaOrganicaController, sufijo: '%', numerico: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _crearProyecto,
          style: ElevatedButton.styleFrom(
            backgroundColor: Marca.neonBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(_editando ? 'Guardar cambios' : 'Crear proyecto'),
        ),
      ],
    );
  }
}

// 2.5 LISTA DE PROYECTOS GUARDADOS (Load file)
class LoadProjectDialog extends StatefulWidget {
  const LoadProjectDialog({super.key});

  @override
  State<LoadProjectDialog> createState() => _LoadProjectDialogState();
}

class _LoadProjectDialogState extends State<LoadProjectDialog> {
  List<Proyecto>? _proyectos; // null = todavía cargando
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _error = null;
      _proyectos = null;
    });
    try {
      final lista = await ProyectoStorage.cargarTodos();
      if (!mounted) return;
      setState(() => _proyectos = lista);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _proyectos = [];
      });
    }
  }

  Future<void> _confirmarEliminar(Proyecto proyecto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Eliminar proyecto'),
        content: Text('¿Seguro que quieres eliminar "${proyecto.nombre}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    try {
      await ProyectoStorage.eliminar(proyecto.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    await _cargar();
  }

  String _formatearFecha(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    Widget contenido;

    if (_proyectos == null) {
      contenido = const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator(color: Marca.neonBlue)),
      );
    } else if (_error != null) {
      contenido = Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: Marca.rocketRed),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Marca.martianRed)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    } else if (_proyectos!.isEmpty) {
      contenido = const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 40, color: Colors.grey),
            SizedBox(height: 10),
            Text('Aún no tienes proyectos guardados.', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 4),
            Text('Crea uno con "New project".', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    } else {
      contenido = ListView.separated(
        shrinkWrap: true,
        itemCount: _proyectos!.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final p = _proyectos![index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Marca.azulSuave,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.eco, size: 18, color: Marca.neonBlue),
            ),
            title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              '${p.superficie.toStringAsFixed(0)} m² · Creado ${_formatearFecha(p.fechaCreacion)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () => _confirmarEliminar(p),
            ),
            onTap: () => Navigator.of(context).pop(p),
          );
        },
      );
    }

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Mis proyectos',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 520,
        height: 380,
        child: contenido,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}

// 3. PINTOR PERSONALIZADO PARA DIBUJAR CIRCULOS CONCENTRICAS DEL FONDO DE LA Welcome Screen
class ConcentricCirclesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    // esto de aqui dibuja tres circulos con radios de 150, 280 y 420 pixeles
    canvas.drawCircle(center, 150, paint);
    canvas.drawCircle(center, 280, paint);
    canvas.drawCircle(center, 420, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
// 4. CAPAS DEL SUELO Y UTILIDADES DE DIBUJO DEL TERRENO
// ============================================================

// Cada capa ocupa una fracción de la profundidad total del perfil
class CapaSuelo {
  final String nombre;
  final double desde; // 0.0 = superficie
  final double hasta; // 1.0 = fondo del perfil
  final Color color;

  const CapaSuelo(this.nombre, this.desde, this.hasta, this.color);

  // Rango en centímetros según la profundidad del proyecto (en metros)
  String rango(double profundidadM) {
    final cm = profundidadM * 100;
    return '${(cm * desde).round()}-${(cm * hasta).round()} cm';
  }
}

const List<CapaSuelo> capasSuelo = [
  CapaSuelo('Materia orgánica', 0.0, 0.10, Color(0xFFD4A373)),
  CapaSuelo('Suelo superficial', 0.10, 0.35, Color(0xFFBC6C25)),
  CapaSuelo('Subsuelo', 0.35, 0.70, Color(0xFF8D6E63)),
  CapaSuelo('Material parental', 0.70, 1.0, Color(0xFF5D4037)),
];

// Elige un tamaño de cuadrícula "redondo" para que haya pocas celdas
double pasoCuadricula(double maximo) {
  const pasos = [1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0];
  for (final p in pasos) {
    if (maximo / p <= 6) return p;
  }
  return pasos.last;
}

// 50.0 -> "50", 24.8 -> "24.8"
String formatoNumero(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

// Dibuja texto dentro de un CustomPainter (centrado o alineado a la izquierda)
void dibujarTexto(
  Canvas canvas,
  String texto,
  Offset posicion, {
  double size = 11,
  Color color = const Color(0xFF333333),
  FontWeight weight = FontWeight.w600,
  double angulo = 0,
  bool alinearIzquierda = false,
}) {
  final tp = TextPainter(
    text: TextSpan(text: texto, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();

  canvas.save();
  canvas.translate(posicion.dx, posicion.dy);
  if (angulo != 0) canvas.rotate(angulo);
  final desplazamiento = alinearIzquierda ? Offset(0, -tp.height / 2) : Offset(-tp.width / 2, -tp.height / 2);
  tp.paint(canvas, desplazamiento);
  canvas.restore();
}

// ============================================================
// 4.1 VISTA 3D: BLOQUE ISOMÉTRICO DEL TERRENO CON SUS CAPAS
// ============================================================
// Grupo visual de la textura (para elegir el dibujo de la superficie)
enum GrupoTextura { arenoso, franco, limoso, arcilloso }

GrupoTextura grupoTextura(String textura) {
  final t = textura.toLowerCase();
  if (t.startsWith('arcill') || t.contains('arcilloso')) return GrupoTextura.arcilloso;
  if (t.contains('arenoso')) return GrupoTextura.arenoso;
  if (t.contains('limoso')) return GrupoTextura.limoso;
  return GrupoTextura.franco;
}

class TerrenoIsometricoPainter extends CustomPainter {
  final double ancho; // metros (lado frontal izquierdo)
  final double largo; // metros (lado frontal derecho)
  final double zoom;

  // Contexto real de la parcela: cambia cómo se ve el terreno
  final String textura; // clase USDA ('Franco', 'Arcilloso', ...); '—' si no hay datos
  final double humedad; // %
  final double materiaOrganica; // %
  final double pendiente; // grados

  const TerrenoIsometricoPainter({
    required this.ancho,
    required this.largo,
    this.zoom = 1,
    this.textura = '—',
    this.humedad = 25,
    this.materiaOrganica = 3,
    this.pendiente = 0,
  });

  GrupoTextura get _grupo => grupoTextura(textura);

  // Color de la superficie: seco = paja, húmedo y fértil = verde intenso
  Color get _colorSuperficie {
    final agua = (humedad / 40).clamp(0.0, 1.0).toDouble();
    final fertil = (materiaOrganica / 6).clamp(0.0, 1.0).toDouble();
    final base = Color.lerp(const Color(0xFFD9C38A), const Color(0xFF6FA35A), agua)!;
    return Color.lerp(base, const Color(0xFF3F7A3A), fertil * 0.45)!;
  }

  // Color del suelo según textura y materia orgánica (más MO = más oscuro)
  Color _colorCapa(CapaSuelo capa, int i) {
    const tinte = {
      GrupoTextura.arenoso: Color(0xFFE2C48E),
      GrupoTextura.franco: Color(0xFFB07A4A),
      GrupoTextura.limoso: Color(0xFFA89276),
      GrupoTextura.arcilloso: Color(0xFFA0522D),
    };
    var c = Color.lerp(capa.color, tinte[_grupo]!, i == 3 ? 0.15 : 0.45)!;
    if (i <= 1) c = Color.lerp(c, const Color(0xFF3E2A1C), (materiaOrganica / 10).clamp(0.0, 0.5).toDouble())!;
    return c;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (ancho <= 0 || largo <= 0) return;
    canvas.clipRect(Offset.zero & size);

    const c = 0.8660254; // cos 30°
    const s = 0.5; // sen 30°
    final a = ancho;
    final l = largo;

    // Grosor del bloque exagerado para que las capas se aprecien
    final grosor = (a + l) * 0.16;

    final anchoIso = (a + l) * c;
    final altoIso = (a + l) * s + grosor;
    final k = math.min((size.width * 0.82) / anchoIso, (size.height * 0.78) / altoIso) * zoom;

    final centro = size.center(Offset.zero);
    final origen = Offset(
      centro.dx - ((a - l) * c * k) / 2,
      centro.dy - (altoIso * k) / 2,
    );

    Offset p(double x, double y, double z) => origen + Offset((x - y) * c * k, (x + y) * s * k + z * k);

    // Semilla fija: el dibujo no "parpadea" al redibujar
    final rng = math.Random((a * 31 + l * 17).round() + _grupo.index * 1000);

    // ---------- Caras laterales, capa por capa ----------
    for (var i = 0; i < capasSuelo.length; i++) {
      final capa = capasSuelo[i];
      final zt = grosor * capa.desde;
      final zb = grosor * capa.hasta;
      final color = _colorCapa(capa, i);

      final caraIzquierda = Path()..addPolygon([p(0, l, zt), p(a, l, zt), p(a, l, zb), p(0, l, zb)], true);
      final caraDerecha = Path()..addPolygon([p(a, 0, zt), p(a, l, zt), p(a, l, zb), p(a, 0, zb)], true);

      canvas.drawPath(caraIzquierda, Paint()..color = color);
      canvas.drawPath(caraDerecha, Paint()..color = Color.lerp(color, Colors.black, 0.22)!);

      // Textura en el corte: granos, grumos, láminas o piedras
      _texturaCorte(canvas, caraIzquierda, (u, v) => p(u * a, l, zt + v * (zb - zt)), color, i, rng, k);
      _texturaCorte(canvas, caraDerecha, (u, v) => p(a, u * l, zt + v * (zb - zt)),
          Color.lerp(color, Colors.black, 0.22)!, i, rng, k);
    }

    // ---------- Cara superior ----------
    final superior = Path()..addPolygon([p(0, 0, 0), p(a, 0, 0), p(a, l, 0), p(0, l, 0)], true);
    canvas.drawPath(superior, Paint()..color = _colorSuperficie);

    canvas.save();
    canvas.clipPath(superior);
    _texturaSuperficie(canvas, (u, v) => p(u * a, v * l, 0), rng, k, a, l);
    canvas.restore();

    // Cuadrícula
    final paso = pasoCuadricula(math.max(a, l));
    final lineas = Paint()
      ..color = const Color(0x3336592E)
      ..strokeWidth = 1;
    for (double x = paso; x < a - 0.001; x += paso) {
      canvas.drawLine(p(x, 0, 0), p(x, l, 0), lineas);
    }
    for (double y = paso; y < l - 0.001; y += paso) {
      canvas.drawLine(p(0, y, 0), p(a, y, 0), lineas);
    }

    // Bordes
    final borde = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(superior, borde);
    canvas.drawLine(p(a, l, 0), p(a, l, grosor), borde);

    // Medidas y etiqueta de textura
    dibujarTexto(canvas, '${formatoNumero(a)} m', p(a / 2, l, grosor) + const Offset(-20, 20));
    dibujarTexto(canvas, '${formatoNumero(l)} m', p(a, l / 2, grosor) + const Offset(20, 20));
    if (textura != '—') {
      dibujarTexto(canvas, 'Textura: $textura', const Offset(10, 14),
          size: 11, color: const Color(0xFF07173F), alinearIzquierda: true);
    }
  }

  // Dibujo de la superficie según la textura del suelo
  void _texturaSuperficie(Canvas canvas, Offset Function(double u, double v) q, math.Random rng,
      double k, double a, double l) {
    final escala = (k * math.sqrt(a * l) / 300).clamp(0.6, 2.0).toDouble(); // tamaño de los detalles en pantalla
    final oscuro = Color.lerp(_colorSuperficie, Colors.black, 0.35)!;
    final claro = Color.lerp(_colorSuperficie, Colors.white, 0.35)!;

    switch (_grupo) {
      case GrupoTextura.arenoso:
        // Granos de arena y ondas de viento
        final grano = Paint()..color = const Color(0xFFF1E3BF);
        for (var i = 0; i < 520; i++) {
          canvas.drawCircle(q(rng.nextDouble(), rng.nextDouble()), (0.6 + rng.nextDouble()) * escala, grano);
        }
        final onda = Paint()
          ..color = const Color(0x55A88B55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (var j = 1; j < 9; j++) {
          final path = Path()..moveTo(q(0, j / 9).dx, q(0, j / 9).dy);
          for (var t = 1; t <= 20; t++) {
            final u = t / 20;
            final pt = q(u, j / 9 + math.sin(u * math.pi * 4 + j) * 0.012);
            path.lineTo(pt.dx, pt.dy);
          }
          canvas.drawPath(path, onda);
        }
        break;

      case GrupoTextura.arcilloso:
        // Grietas de suelo arcilloso (más marcadas si está seco)
        final grieta = Paint()
          ..color = oscuro.withValues(alpha: humedad < 25 ? 0.75 : 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 * escala;
        for (var i = 0; i < 26; i++) {
          var u = rng.nextDouble(), v = rng.nextDouble();
          final path = Path()..moveTo(q(u, v).dx, q(u, v).dy);
          for (var t = 0; t < 4 + rng.nextInt(4); t++) {
            u += (rng.nextDouble() - 0.5) * 0.12;
            v += (rng.nextDouble() - 0.5) * 0.12;
            final pt = q(u, v);
            path.lineTo(pt.dx, pt.dy);
          }
          canvas.drawPath(path, grieta);
        }
        break;

      case GrupoTextura.limoso:
        // Superficie lisa con vetas finas
        final veta = Paint()
          ..color = claro.withValues(alpha: 0.6)
          ..strokeWidth = 0.9;
        for (var i = 0; i < 160; i++) {
          final u = rng.nextDouble(), v = rng.nextDouble();
          canvas.drawLine(q(u, v), q(u + 0.04 + rng.nextDouble() * 0.04, v), veta);
        }
        break;

      case GrupoTextura.franco:
        // Grumos de tierra mezclados
        final grumo = Paint()..color = oscuro.withValues(alpha: 0.45);
        for (var i = 0; i < 220; i++) {
          final centro = q(rng.nextDouble(), rng.nextDouble());
          canvas.drawOval(
              Rect.fromCenter(center: centro, width: (2 + rng.nextDouble() * 3) * escala, height: (1.2 + rng.nextDouble() * 1.5) * escala),
              grumo);
        }
        break;
    }

    // Matas de pasto: más cuanto más húmeda y fértil
    final cantidad = (40 * (humedad / 35).clamp(0.0, 1.5) * (0.5 + materiaOrganica / 8)).round().clamp(0, 120);
    final pasto = Paint()
      ..color = const Color(0xFF2F6B2A)
      ..strokeWidth = 1.2 * escala
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < cantidad; i++) {
      final b = q(rng.nextDouble(), rng.nextDouble());
      final h = (4 + rng.nextDouble() * 4) * escala;
      canvas.drawLine(b, b + Offset(-2 * escala, -h), pasto);
      canvas.drawLine(b, b + Offset(0, -h * 1.2), pasto);
      canvas.drawLine(b, b + Offset(2 * escala, -h), pasto);
    }
  }

  // Dibujo dentro de cada capa del corte lateral
  void _texturaCorte(Canvas canvas, Path cara, Offset Function(double u, double v) q, Color color, int capa,
      math.Random rng, double k) {
    canvas.save();
    canvas.clipPath(cara);
    final oscuro = Paint()..color = Color.lerp(color, Colors.black, 0.3)!.withValues(alpha: 0.6);
    final claro = Paint()..color = Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: 0.7);

    if (capa == 0) {
      // Materia orgánica: raíces finas, más con más MO
      final raiz = Paint()
        ..color = const Color(0xAA4E342E)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final n = (8 + materiaOrganica * 3).round().clamp(6, 40);
      for (var i = 0; i < n; i++) {
        final u = rng.nextDouble();
        final path = Path()..moveTo(q(u, 0).dx, q(u, 0).dy);
        final fin = q(u + (rng.nextDouble() - 0.5) * 0.03, 0.6 + rng.nextDouble() * 0.4);
        path.lineTo(fin.dx, fin.dy);
        canvas.drawPath(path, raiz);
      }
    } else if (capa == 3) {
      // Material parental: piedras
      for (var i = 0; i < 14; i++) {
        final centro = q(rng.nextDouble(), rng.nextDouble());
        final r = 2 + rng.nextDouble() * 4;
        canvas.drawOval(Rect.fromCenter(center: centro, width: r * 2, height: r * 1.3), claro);
      }
    } else {
      switch (_grupo) {
        case GrupoTextura.arenoso:
          for (var i = 0; i < 140; i++) {
            canvas.drawCircle(q(rng.nextDouble(), rng.nextDouble()), 0.9, claro);
          }
          break;
        case GrupoTextura.limoso:
          final lamina = Paint()
            ..color = claro.color
            ..strokeWidth = 0.8;
          for (var j = 1; j < 6; j++) {
            canvas.drawLine(q(0, j / 6), q(1, j / 6), lamina);
          }
          break;
        case GrupoTextura.arcilloso:
          // Bloques compactos
          final linea = Paint()
            ..color = oscuro.color
            ..strokeWidth = 0.9;
          for (var j = 0; j < 22; j++) {
            final u = rng.nextDouble();
            canvas.drawLine(q(u, 0), q(u + 0.01, 1), linea);
          }
          break;
        case GrupoTextura.franco:
          for (var i = 0; i < 60; i++) {
            canvas.drawCircle(q(rng.nextDouble(), rng.nextDouble()), 1.4, oscuro);
          }
          break;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TerrenoIsometricoPainter old) =>
      old.ancho != ancho ||
      old.largo != largo ||
      old.zoom != zoom ||
      old.textura != textura ||
      old.humedad != humedad ||
      old.materiaOrganica != materiaOrganica ||
      old.pendiente != pendiente;
}

// ============================================================
// 4.2 VISTA 2D: PLANTA DEL TERRENO + CORTE DEL PERFIL
// ============================================================
class TerrenoPlantaPainter extends CustomPainter {
  final double ancho;
  final double largo;
  final double profundidad;
  final double zoom;

  const TerrenoPlantaPainter({
    required this.ancho,
    required this.largo,
    required this.profundidad,
    this.zoom = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ancho <= 0 || largo <= 0) return;
    canvas.clipRect(Offset.zero & size);

    const gris = Color(0xFF8A8A8A);
    const verdeOscuro = Color(0xFF2D5A27);
    final w = size.width;
    final h = size.height;
    final altoPlanta = h * 0.56;

    // ---------- PLANTA ----------
    final paso = pasoCuadricula(math.max(ancho, largo));
    dibujarTexto(canvas, 'Cuadrícula: ${formatoNumero(paso)} m', const Offset(0, 8),
        size: 9, color: gris, weight: FontWeight.w500, alinearIzquierda: true);

    final k = math.min((w * 0.5) / ancho, (altoPlanta - 60) / largo) * zoom;
    final rect = Rect.fromCenter(
      center: Offset(w / 2, altoPlanta / 2 + 4),
      width: ancho * k,
      height: largo * k,
    );

    canvas.drawRect(rect, Paint()..color = const Color(0xFFDCE8D6));

    final lineas = Paint()
      ..color = const Color(0x332D5A27)
      ..strokeWidth = 1;
    for (double x = paso; x < ancho - 0.001; x += paso) {
      canvas.drawLine(Offset(rect.left + x * k, rect.top), Offset(rect.left + x * k, rect.bottom), lineas);
    }
    for (double y = paso; y < largo - 0.001; y += paso) {
      canvas.drawLine(Offset(rect.left, rect.top + y * k), Offset(rect.right, rect.top + y * k), lineas);
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = verdeOscuro
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    dibujarTexto(canvas, '${formatoNumero(ancho)} m', Offset(rect.center.dx, rect.bottom + 14), size: 11);
    dibujarTexto(canvas, '${formatoNumero(largo)} m', Offset(rect.left - 14, rect.center.dy), size: 11, angulo: -math.pi / 2);

    // Flecha del norte
    final flecha = Paint()
      ..color = gris
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(w - 24, 50), Offset(w - 24, 20), flecha);
    canvas.drawPath(
      Path()
        ..moveTo(w - 24, 14)
        ..lineTo(w - 28.5, 22)
        ..lineTo(w - 19.5, 22)
        ..close(),
      Paint()..color = gris,
    );
    dibujarTexto(canvas, 'N', Offset(w - 24, 60), size: 9, color: gris);

    dibujarTexto(canvas, 'PLANTA', Offset(0, altoPlanta + 4),
        size: 9, color: gris, weight: FontWeight.w700, alinearIzquierda: true);

    // ---------- CORTE DEL PERFIL ----------
    final topCorte = altoPlanta + 28;
    dibujarTexto(canvas, 'CORTE DEL PERFIL', Offset(0, topCorte),
        size: 9, color: gris, weight: FontWeight.w700, alinearIzquierda: true);

    final yInicio = topCorte + 14;
    final altoCorte = math.max(40.0, h - yInicio - 4);
    const xInicio = 78.0;

    for (int i = 0; i < capasSuelo.length; i++) {
      final capa = capasSuelo[i];
      final y0 = yInicio + altoCorte * capa.desde;
      final y1 = yInicio + altoCorte * capa.hasta;
      final medio = (y0 + y1) / 2;

      canvas.drawRect(Rect.fromLTRB(xInicio, y0, w, y1), Paint()..color = capa.color);

      dibujarTexto(canvas, capa.nombre, Offset(xInicio + 10, medio),
          size: 10,
          color: i == 0 ? const Color(0xFF3E2A1A) : Colors.white,
          weight: FontWeight.w700,
          alinearIzquierda: true);

      dibujarTexto(canvas, capa.rango(profundidad), Offset(0, medio),
          size: 9.5, color: gris, weight: FontWeight.w400, alinearIzquierda: true);
    }
  }

  @override
  bool shouldRepaint(covariant TerrenoPlantaPainter old) =>
      old.ancho != ancho || old.largo != largo || old.profundidad != profundidad || old.zoom != zoom;
}

// ============================================================
// 5. PANTALLA 2: DASHBOARD SCREEN (Pantalla principal de la app)
// Diseño adaptable: se acomoda a cualquier tamaño de ventana.
// ============================================================
class DashboardScreen extends StatefulWidget {
  final Proyecto proyecto; // Proyecto que se está visualizando

  const DashboardScreen({super.key, required this.proyecto});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Llave para abrir/cerrar el menú lateral cuando la ventana es angosta
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = 0; // 0 = Terreno
  bool _vista3D = true; // true = 3D, false = 2D
  double _zoom = 1.0;

  // Sección Cultivar: controla el desplazamiento de la fila de tarjetas
  final _cultivosScroll = ScrollController();
  int _cultivoSeleccionado = 0;

  // Sección Cultivar: fichas que llegan del archivo BDPLANS_cultivos.csv (por el servidor)
  Map<String, FichaCultivo> _fichas = {};
  bool _cargandoFichas = false;
  String? _errorFichas;

  // Sección Proyección: vista "Rotación" (simulación Monte Carlo del servidor)
  bool _vistaRotacion = false;
  bool _rotacionConRiego = false;
  int _largoRotacion = 4; // Cultivos por rotación (3 o 4)
  final Map<String, ResultadoRotacion> _rotaciones = {}; // Resultados guardados por (pH, profundidad, riego)
  bool _cargandoRotacion = false;
  String? _errorRotacion;

  // Clave para no repetir la simulación si no cambió nada
  // Incluye la ubicación: si la parcela cambia de lugar, se vuelve a simular
  String get _claveRotacion =>
      '${_p.latitud}|${_p.longitud}|${_p.ph}|${_p.profundidad}|${_p.humedad}|${_p.materiaOrganica}|'
      '${_suelo?.arcilla}|${_suelo?.arena}|$_rotacionConRiego|$_largoRotacion';
  ResultadoRotacion? get _rotacionActual => _rotaciones[_claveRotacion];

  // Sección Terreno: datos de suelo de la API (Earth Engine / OpenLandMap)
  DatosSuelo? _suelo;
  bool _cargandoSuelo = false;
  String? _errorSuelo;

  // Sección Clima: datos reales que llegan del servidor (Meteomatics)
  DatosClima? _clima;
  bool _cargandoClima = false;
  String? _errorClima;

  @override
  void initState() {
    super.initState();
    // Pide el clima en cuanto se abre el proyecto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarClima();
      _cargarFichas();
      _cargarSuelo();
    });

    // Actualizador: cada 5 minutos vuelve a pedir el clima sin que el usuario haga nada
    _actualizador = Timer.periodic(_intervaloActualizacion, (_) => _cargarClima(silencioso: true));
  }

  // ---------------- ACTUALIZADOR AUTOMÁTICO ----------------
  static const Duration _intervaloActualizacion = Duration(minutes: 5);
  Timer? _actualizador;

  // Pide a la API de suelo los datos de la parcela y los guarda en el proyecto
  Future<void> _cargarSuelo() async {
    if (_cargandoSuelo) return;
    setState(() {
      _cargandoSuelo = true;
      _errorSuelo = null;
    });

    try {
      final datos = await SueloService.obtener(_p.latitud, _p.longitud);
      if (!mounted) return;

      // Los valores de la API reemplazan a los que se escribieron a mano
      final actualizado = _proyecto.conSuelo(
        humedad: datos.humedad ?? _proyecto.humedad,
        ph: datos.ph ?? _proyecto.ph,
        materiaOrganica: datos.materiaOrganica ?? _proyecto.materiaOrganica,
      );
      setState(() {
        _suelo = datos;
        _proyecto = actualizado;
      });

      // Se guardan en proyectos.json para que la próxima vez ya estén ahí
      try {
        await ProyectoStorage.guardar(actualizado);
      } catch (_) {
        // Si no se pudo guardar, los datos igual se muestran en pantalla
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorSuelo = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargandoSuelo = false);
    }
  }

  // Pide al servidor la simulación Monte Carlo de rotaciones
  Future<void> _simularRotacion({bool repetir = false}) async {
    if (_cargandoRotacion) return;
    if (!repetir && _rotacionActual != null) return; // Ya estaba calculada
    final clave = _claveRotacion;

    setState(() {
      _cargandoRotacion = true;
      _errorRotacion = null;
    });
    try {
      final resultado = await RotacionService.obtener(
        latitud: _p.latitud,
        longitud: _p.longitud,
        ph: _p.ph,
        profundidad: _p.profundidad,
        riego: _rotacionConRiego,
        largo: _largoRotacion,
        // Datos extra del suelo para que la simulación sea más precisa
        humedad: _p.humedad,
        materiaOrganica: _p.materiaOrganica,
        arcilla: _suelo?.arcilla,
        arena: _suelo?.arena,
        elevacion: _suelo?.elevacion,
        pendiente: _suelo?.pendiente,
      );
      if (!mounted) return;
      setState(() => _rotaciones[clave] = resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorRotacion = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargandoRotacion = false);
    }
  }

  // Pide al servidor los datos del archivo de cultivos
  Future<void> _cargarFichas() async {
    if (_cargandoFichas) return;
    setState(() {
      _cargandoFichas = true;
      _errorFichas = null;
    });

    try {
      final fichas = await CultivosService.obtener();
      if (!mounted) return;
      setState(() => _fichas = fichas);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorFichas = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargandoFichas = false);
    }
  }

  // Cultivo seleccionado con los valores del archivo (si existen) en lugar de los de ejemplo
  Cultivo get _cultivoActual {
    final c = cultivos[_cultivoSeleccionado];
    final f = _fichas[c.nombre];
    if (f == null) return c;
    return Cultivo(
      c.nombre,
      c.tipo,
      c.color,
      dias: f.cicloPromedio ?? c.dias,
      rendimiento: c.rendimiento, // El archivo no trae rendimiento
      phMin: f.phMinOpt ?? c.phMin,
      phMax: f.phMaxOpt ?? c.phMax,
      tempMin: f.tempMinOpt ?? c.tempMin,
      tempMax: f.tempMaxOpt ?? c.tempMax,
      humMin: c.humMin,
      humMax: c.humMax,
    );
  }

  // Texto pequeño de cada tarjeta de cultivo
  String _datoCorto(String nombre) {
    final f = _fichas[nombre];
    if (f != null) return f.resumen;
    if (_cargandoFichas) return 'Cargando...';
    if (_fichas.isNotEmpty) return 'Sin datos en el archivo';
    return 'info';
  }

  // Qué tan bien se adapta el cultivo a la parcela (pH, temperatura y profundidad)
  ({String nivel, String detalle}) _compatibilidad(FichaCultivo f) {
    int puntos = 0;
    int maximo = 0;
    final criterios = <String>[];

    int evaluar(double? valor, double? minOpt, double? maxOpt, double? minAbs, double? maxAbs) {
      if (valor == null || minOpt == null || maxOpt == null) return -1;
      if (valor >= minOpt && valor <= maxOpt) return 2;
      if (valor >= (minAbs ?? minOpt) && valor <= (maxAbs ?? maxOpt)) return 1;
      return 0;
    }

    String marca(int p) => p == 2 ? '✓' : (p == 1 ? '~' : '✗');

    final ph = evaluar(_p.ph, f.phMinOpt, f.phMaxOpt, f.phMinAbs, f.phMaxAbs);
    if (ph >= 0) {
      puntos += ph;
      maximo += 2;
      criterios.add('pH ${marca(ph)}');
    }

    final temp = evaluar(_clima?.temperatura, f.tempMinOpt, f.tempMaxOpt, f.tempMinAbs, f.tempMaxAbs);
    if (temp >= 0) {
      puntos += temp;
      maximo += 2;
      criterios.add('Temp ${marca(temp)}');
    }

    final profundidadNecesaria = f.profundidadMinimaM;
    if (profundidadNecesaria != null) {
      final p = _p.profundidad >= profundidadNecesaria ? 2 : (_p.profundidad >= profundidadNecesaria * 0.6 ? 1 : 0);
      puntos += p;
      maximo += 2;
      criterios.add('Prof. ${marca(p)}');
    }

    if (maximo == 0) return (nivel: '—', detalle: 'Sin datos para comparar');
    final porcentaje = puntos / maximo;
    final nivel = porcentaje >= 0.8 ? 'Alta' : (porcentaje >= 0.5 ? 'Media' : 'Baja');
    return (nivel: nivel, detalle: criterios.join('  ·  '));
  }

  // Ventana con todos los campos del archivo para un cultivo
  void _verFicha(Cultivo c) {
    final f = _fichas[c.nombre];
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorFichas != null
              ? 'No se pudo leer el archivo de cultivos: $_errorFichas'
              : '${c.nombre} no aparece en el archivo de cultivos.'),
        ),
      );
      return;
    }
    showDialog(context: context, builder: (context) => FichaCultivoDialog(nombre: c.nombre, ficha: f));
  }

  // Consulta el clima de las coordenadas del proyecto
  // silencioso: true cuando lo llama el actualizador (no muestra el circulito de carga
  //             ni borra los datos que ya se ven en pantalla).
  // forzar: true cuando el usuario presiona ⟳ (el servidor ignora su copia guardada).
  Future<void> _cargarClima({bool silencioso = false, bool forzar = false}) async {
    if (_cargandoClima) return;
    if (!silencioso) {
      setState(() {
        _cargandoClima = true;
        _errorClima = null;
      });
    }

    try {
      final datos = await ClimaService.obtener(_p.latitud, _p.longitud, forzar: forzar);
      if (!mounted) return;
      setState(() {
        _clima = datos;
        _errorClima = null;
      });
    } catch (e) {
      if (!mounted) return;
      // En modo silencioso solo se avisa si todavía no había datos en pantalla
      if (!silencioso || _clima == null) {
        setState(() => _errorClima = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && !silencioso) setState(() => _cargandoClima = false);
    }
  }

  // Botón ⟳: actualiza ya, pidiendo datos nuevos a Meteomatics
  void _actualizarAhora() => _cargarClima(forzar: true);

  @override
  void dispose() {
    _actualizador?.cancel(); // Detiene el actualizador al salir de la pantalla
    _cultivosScroll.dispose();
    super.dispose();
  }

  // Secciones del menú lateral (nombre corto, título y subtítulo)
  static const List<String> _secciones = ['Terreno', 'Clima', 'Cultivar', 'Proyección'];
  static const List<String> _titulos = [
    'Conoce tu terreno',
    'Clima y Pronóstico',
    'Cultivar y Recomendaciones',
    'Proyección Agrícola',
  ];
  static const List<String> _subtitulos = [
    'Explora lo que hay bajo la superficie. Descubre lo que puede crecer.',
    'Consulta el clima de tu parcela y planea tus labores con anticipación.',
    'Descubre qué cultivos se adaptan mejor a tu terreno.',
    'Estima cómo podría evolucionar tu próxima cosecha.',
  ];

  // Colores y estilos que se repiten
  static const _acento = Marca.neonBlue; // Color de acento (antes verde)
  static const _tinta = Marca.deepBlue; // Texto principal / títulos
  static const _gris = TextStyle(fontSize: 11, color: Colors.grey);

  // Copia del proyecto que se puede actualizar al editarlo
  late Proyecto _proyecto = widget.proyecto;
  Proyecto get _p => _proyecto;

  // Abre el formulario con los datos actuales; si se guardan, se actualiza todo
  Future<void> _configurarTerreno() async {
    final editado = await showDialog<Proyecto>(
      context: context,
      barrierDismissible: false,
      builder: (context) => NewProjectDialog(proyectoInicial: _proyecto),
    );

    if (editado == null) return; // Canceló

    try {
      await ProyectoStorage.guardar(editado); // Reemplaza el guardado (mismo id)
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    if (!mounted) return;

    final cambioUbicacion = editado.latitud != _proyecto.latitud || editado.longitud != _proyecto.longitud;
    setState(() => _proyecto = editado);
    if (cambioUbicacion) {
      _cargarClima();
      _cargarSuelo();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Terreno actualizado correctamente.')),
    );
  }

  // ---------------- LÓGICA ----------------

  // Regresa a la pantalla de bienvenida (New project / Load file)
  void _volverAlInicio() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
    );
  }

  // Coordenadas en formato "37.3891° N - 5.9845° O"
  String get _coordenadasTexto {
    final lat = '${_p.latitud.abs().toStringAsFixed(4)}° ${_p.latitud >= 0 ? 'N' : 'S'}';
    final lon = '${_p.longitud.abs().toStringAsFixed(4)}° ${_p.longitud >= 0 ? 'E' : 'O'}';
    return '$lat - $lon';
  }

  // Estados calculados a partir de los valores del proyecto
  String get _estadoHumedad {
    if (_p.humedad < 15) return 'Suelo seco';
    if (_p.humedad <= 35) return 'Nivel adecuado';
    return 'Exceso de humedad';
  }

  String get _estadoPh {
    if (_p.ph < 5.5) return 'Ácido';
    if (_p.ph < 6.8) return 'Ligeramente ácido';
    if (_p.ph <= 7.2) return 'Neutro';
    if (_p.ph <= 8.0) return 'Ligeramente alcalino';
    return 'Alcalino';
  }

  String get _estadoMateriaOrganica {
    if (_p.materiaOrganica < 2) return 'Fertilidad baja';
    if (_p.materiaOrganica <= 5) return 'Buena fertilidad';
    return 'Fertilidad alta';
  }

  // Painter de la vista activa del terreno (3D o 2D)
  CustomPainter _painterActual(double zoom) {
    if (_vista3D) {
      return TerrenoIsometricoPainter(
        ancho: _p.ancho,
        largo: _p.largo,
        zoom: zoom,
        textura: _suelo?.textura ?? '—',
        humedad: _p.humedad,
        materiaOrganica: _p.materiaOrganica,
        pendiente: _suelo?.pendiente ?? 0,
      );
    }
    return TerrenoPlantaPainter(ancho: _p.ancho, largo: _p.largo, profundidad: _p.profundidad, zoom: zoom);
  }

  void _cambiarZoom(double delta) {
    setState(() => _zoom = (_zoom + delta).clamp(0.5, 2.0));
  }

  // Muestra el modelo del terreno en grande
  void _pantallaCompleta() {
    final tamano = MediaQuery.sizeOf(context);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: tamano.width * 0.9,
          height: tamano.height * 0.85,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_p.nombre} · ${_vista3D ? 'Vista 3D' : 'Vista 2D'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(child: SizedBox.expand(child: CustomPaint(painter: _painterActual(1)))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- PANTALLA ----------------

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final menuFijo = ancho >= 1000; // Menú lateral siempre visible
    final compacto = ancho < 700; // Pantallas pequeñas

    return Scaffold(
      key: _scaffoldKey,
      drawer: menuFijo
          ? null
          : Drawer(
              width: 260,
              backgroundColor: Marca.deepBlue,
              child: _menuLateral(),
            ),
      body: Row(
        children: [
          if (menuFijo) SizedBox(width: 240, child: _menuLateral()),
          Expanded(child: _areaPrincipal(menuFijo, compacto)),
        ],
      ),
    );
  }

  // ---------------- MENÚ LATERAL ----------------
  Widget _menuLateral() {
    return FondoMarca(
      variante: 1,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: ConstrainedBox(
              // Ocupa todo el alto disponible, y si no cabe permite desplazarse
              constraints: BoxConstraints(minHeight: math.max(0.0, constraints.maxHeight - 48)),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo y nombre
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white70),
                          ),
                          child: const Icon(Icons.eco, color: Marca.white, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Text('FARM-EK', style: Marca.titulo(size: 16, color: Marca.white, peso: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('PROYECTO ACTUAL', style: TextStyle(color: Marca.blueYonder, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 8),

                    // Selector del proyecto actual: abre la lista de proyectos guardados
                    Material(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => abrirProyectoGuardado(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _p.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Marca.white),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('EXPLORAR', style: TextStyle(color: Marca.blueYonder, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 10),

                    _buildNavItem(0, Icons.layers_outlined, 'Terreno'),
                    _buildNavItem(1, Icons.wb_sunny_outlined, 'Clima'),
                    _buildNavItem(2, Icons.grass_outlined, 'Cultivar'),
                    _buildNavItem(3, Icons.show_chart_outlined, 'Proyección'),

                    const Spacer(),
                    const SizedBox(height: 16),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _abrirGuia,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.help_outline, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text('Guía de exploración',
                                    style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                              Icon(Icons.chevron_right, size: 16, color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Abre la guía; si eligen "Ir a esta sección", cambia a esa sección
  Future<void> _abrirGuia() async {
    _scaffoldKey.currentState?.closeDrawer();
    final destino = await showDialog<int>(
      context: context,
      builder: (_) => GuiaExploracionDialog(seccionInicial: _selectedIndex),
    );
    if (destino != null && mounted) setState(() => _selectedIndex = destino);
  }

  // Elemento del menú lateral
  Widget _buildNavItem(int index, IconData icon, String title) {
    final seleccionado = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: seleccionado ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _selectedIndex = index);
            _scaffoldKey.currentState?.closeDrawer(); // Cierra el menú si estaba desplegado
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                // Barrita Neon Yellow solo en la sección activa
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 3,
                  height: 18,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: seleccionado ? Marca.neonYellow : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(icon, size: 18, color: seleccionado ? Marca.white : Colors.white70),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
                      color: seleccionado ? Marca.white : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- ÁREA PRINCIPAL ----------------
  Widget _areaPrincipal(bool menuFijo, bool compacto) {
    final esClima = _selectedIndex == 1;
    final esCultivar = _selectedIndex == 2;
    final esProyeccion = _selectedIndex == 3;

    // Tarjeta grande según la sección elegida
    final Widget tarjetaPrincipal;
    if (esClima) {
      tarjetaPrincipal = _tarjetaClima(compacto);
    } else if (esCultivar) {
      tarjetaPrincipal = _tarjetaCultivar(compacto);
    } else if (esProyeccion) {
      tarjetaPrincipal = _tarjetaProyeccion(compacto);
    } else {
      tarjetaPrincipal = _tarjetaTerreno(compacto);
    }

    // Tarjetas pequeñas de abajo según la sección elegida
    final List<Widget> tarjetasInferiores;
    if (esClima) {
      tarjetasInferiores = [
        _buildMetricCard('Radiación', _valor(_clima?.radiacion, 0, 'W/m²'),
            _clima?.radiacion == null ? _estadoCarga : nivelRadiacion(_clima!.radiacion!), Icons.wb_sunny_outlined),
        _buildMetricCard('Humedad', _valor(_clima?.humedad, 0, '%'),
            _clima?.humedad == null ? _estadoCarga : nivelHumedadAire(_clima!.humedad!), Icons.water_drop_outlined),
        _buildMetricCard('Temperatura', _valor(_clima?.temperatura, 1, '°C'),
            _clima?.temperatura == null ? _estadoCarga : nivelTemperatura(_clima!.temperatura!), Icons.thermostat_outlined),
        _buildMetricCard('Evaporación (última hora)', _valor(_clima?.evaporacion, 2, 'mm'),
            _clima?.evaporacion == null ? _estadoCarga : nivelEvaporacion(_clima!.evaporacion!), Icons.waves),
      ];
    } else if (esCultivar) {
      final cultivo = _cultivoActual;
      final f = _fichas[cultivo.nombre];
      final sinDato = _cargandoFichas ? 'Cargando...' : 'Sin dato';
      final compat = f == null ? null : _compatibilidad(f);
      tarjetasInferiores = [
        _buildMetricCard('Cultivo seleccionado', cultivo.nombre, f?.cientifico ?? cultivo.tipo, Icons.eco_outlined),
        _buildMetricCard(
          'Temperatura óptima',
          f?.tempMinOpt == null ? '—' : '${formatoNumero(f!.tempMinOpt!)}–${formatoNumero(f.tempMaxOpt ?? 0.0)} °C',
          f?.tempMinAbs == null ? sinDato : 'Tolera de ${formatoNumero(f!.tempMinAbs!)} a ${formatoNumero(f.tempMaxAbs ?? 0.0)} °C',
          Icons.thermostat_outlined,
        ),
        _buildMetricCard(
          'pH óptimo',
          f?.phMinOpt == null ? '—' : '${formatoNumero(f!.phMinOpt!)}–${formatoNumero(f.phMaxOpt ?? 0.0)}',
          f == null ? sinDato : 'Tu suelo: ${formatoNumero(_p.ph)} pH',
          Icons.science_outlined,
        ),
        _buildMetricCard(
          'Ciclo de cultivo',
          f?.cicloMin == null ? '—' : '${f!.cicloMin!.round()}–${(f.cicloMax ?? f.cicloMin!).round()} días',
          f?.cicloVida ?? sinDato,
          Icons.calendar_month_outlined,
        ),
        _buildMetricCard(
          'Compatibilidad con tu parcela',
          compat?.nivel ?? '—',
          compat?.detalle ?? sinDato,
          Icons.check_circle_outline,
        ),
      ];
    } else if (esProyeccion && _vistaRotacion) {
      final r = _rotacionActual;
      final mejor = r?.mejor;
      final esperando = _cargandoRotacion ? 'Simulando...' : 'Sin simular';
      tarjetasInferiores = [
        _buildMetricCard('Probabilidad de éxito', mejor == null ? '—' : '${(mejor.exito * 100).toStringAsFixed(1)} %',
            mejor == null ? esperando : (_rotacionConRiego ? 'Con riego' : 'Sin riego'), Icons.verified_outlined),
        _buildMetricCard('Riego necesario', mejor?.riegoMm == null ? '—' : '${conMiles(mejor!.riegoMm!)} L/m²',
            mejor?.riegoMm == null ? esperando : '${conMiles(mejor!.riegoMm! * _p.superficie)} L en tu parcela', Icons.water_drop_outlined),
        _buildMetricCard('Duración de la rotación', mejor == null ? '—' : '${formatoNumero(mejor.meses)} meses',
            mejor == null ? esperando : '${mejor.rotacion.length} cultivos', Icons.date_range_outlined),
        _buildMetricCard('Futuros simulados', r == null ? '—' : conMiles(r.simulaciones),
            r == null ? esperando : '${conMiles(r.rotacionesEvaluadas)} rotaciones probadas', Icons.auto_graph),
      ];
    } else if (esProyeccion) {
      final cultivo = _cultivoActual;
      final kilos = _p.superficie * cultivo.rendimiento;
      final cosecha = DateTime.now().add(Duration(days: cultivo.dias));
      final aguaPorM2 = _evaporacionDia * 0.9; // 1 mm de evaporación = 1 L por m²
      final cumplidas = _condicionesCumplidas(cultivo);
      tarjetasInferiores = [
        _buildMetricCard('Rendimiento estimado', '${conMiles(kilos)} kg', '${formatoNumero(_p.superficie)} m² × ${formatoNumero(cultivo.rendimiento)} kg/m²', Icons.inventory_2_outlined),
        _buildMetricCard('Días a cosecha', '${cultivo.dias} días', 'Cosecha: ${fechaCorta(cosecha)}', Icons.event_available_outlined),
        _buildMetricCard('Agua necesaria', '${aguaPorM2.toStringAsFixed(1)} L/m²', '${conMiles(aguaPorM2 * _p.superficie)} L al día en tu parcela', Icons.water_drop_outlined),
        _buildMetricCard('Nivel de viabilidad', _textoViabilidad(cumplidas), '$cumplidas de 4 condiciones ideales', Icons.verified_outlined),
      ];
    } else {
      tarjetasInferiores = [
        _buildMetricCard('Humedad del suelo', '${formatoNumero(_p.humedad)} %', _estadoHumedad, Icons.water_drop_outlined),
        _buildMetricCard('pH del suelo', '${formatoNumero(_p.ph)} pH', _suelo?.estadoPh ?? _estadoPh, Icons.science_outlined),
        _buildMetricCard('Materia orgánica', '${formatoNumero(_p.materiaOrganica)} %',
            _suelo?.estadoMateriaOrganica ?? _estadoMateriaOrganica, Icons.eco_outlined),
        _buildMetricCard(
          'Textura del suelo',
          _suelo?.textura ?? '—',
          _suelo == null
              ? (_cargandoSuelo ? 'Consultando...' : 'Sin dato')
              : 'Arcilla ${formatoNumero(_suelo!.arcilla ?? 0.0)}% · Limo ${formatoNumero(_suelo!.limo ?? 0.0)}% · Arena ${formatoNumero(_suelo!.arena ?? 0.0)}%',
          Icons.grain,
        ),
      ];
    }

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _barraSuperior(menuFijo, compacto),
        const SizedBox(height: 20),
        _titulo(compacto),
        const SizedBox(height: 16),
        Expanded(child: tarjetaPrincipal),
        const SizedBox(height: 16),
        _filaTarjetas(tarjetasInferiores),
        const SizedBox(height: 8),

        // Pie de página
        Row(
          children: [
            const Expanded(
              child: Text(
                'Datos guardados en este equipo · Un punto de partida para tu próxima cosecha.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '0${_selectedIndex + 1} / 0${_secciones.length} — ${_secciones[_selectedIndex]}',
              style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(compacto ? 16 : 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Si la ventana es muy baja, la página se puede desplazar en vez de apretarse
            final altoMinimo = compacto ? 860.0 : 680.0;
            if (constraints.maxHeight >= altoMinimo) return contenido;
            return SingleChildScrollView(
              child: SizedBox(height: altoMinimo, child: contenido),
            );
          },
        ),
      ),
    );
  }

  // Barra superior: botón Menú, migas de pan y usuario
  Widget _barraSuperior(bool menuFijo, bool compacto) {
    return Row(
      children: [
        // Botón para desplegar el menú lateral (solo en ventanas angostas)
        if (!menuFijo) ...[
          IconButton(
            tooltip: 'Secciones',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu, color: _tinta),
          ),
          const SizedBox(width: 4),
        ],

        // Botón para volver a la pantalla de inicio
        OutlinedButton(
          onPressed: _volverAlInicio,
          style: OutlinedButton.styleFrom(
            foregroundColor: _tinta,
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chevron_left, size: 18),
              if (!compacto) ...[
                const SizedBox(width: 4),
                const Text('Menú', style: TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Nombre del proyecto: ocupa TODO el espacio libre (Expanded),
        // por eso empuja el grupo de la derecha hasta la orilla.
        Expanded(
          child: Text(
            _p.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),

        // Grupo derecho: siempre pegado a la orilla derecha
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Marca.azulSuave,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.eco, size: 14, color: _acento),
              if (!compacto) ...[
                const SizedBox(width: 6),
                const Text('Proyecto local', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _tinta)),
              ],
            ],
          ),
        ),
        if (!compacto) ...[
          const SizedBox(width: 12),
          const Icon(Icons.more_horiz, color: Colors.grey),
        ],
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Marca.azulSeleccion,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('EK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _tinta)),
        ),
      ],
    );
  }

  // Título de la sección y botón "Configurar terreno"
  Widget _titulo(bool compacto) {
    return FondoMarca(
      variante: _selectedIndex,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 24, vertical: compacto ? 14 : 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SECCIÓN 0${_selectedIndex + 1}  ·  ${_secciones[_selectedIndex].toUpperCase()}',
                    style: const TextStyle(color: Marca.neonYellow, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _titulos[_selectedIndex],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Marca.titulo(size: compacto ? 22 : 28, color: Marca.white, peso: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitulos[_selectedIndex],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            // Solo aparece en la sección Terreno
            if (_selectedIndex == 0) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Marca.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.symmetric(horizontal: compacto ? 10 : 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _configurarTerreno,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune, size: 16, color: Marca.white),
                    if (!compacto) ...[
                      const SizedBox(width: 8),
                      const Text('Configurar terreno', style: TextStyle(color: Marca.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- TARJETA: MODELO DEL TERRENO ----------------
  Widget _tarjetaTerreno(bool compacto) {
    return Container(
      padding: EdgeInsets.all(compacto ? 14 : 20),
      decoration: _decoracionTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _encabezadoTarjeta(
                  Icons.layers_outlined,
                  'MODELO DEL TERRENO  /  ${_p.nombre.toUpperCase()}',
                  _vista3D
                      ? '• PERSPECTIVA ISOMÉTRICA  ·  suelo: ${_suelo != null ? 'Earth Engine (OpenLandMap)' : 'datos del proyecto'}'
                      : '• VISTA 2D  ·  PLANTA Y CORTE',
                ),
              ),
              const SizedBox(width: 12),
              _cargandoSuelo
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _acento))
                  : _botonFlecha(Icons.refresh, 'Actualizar datos del suelo', _cargarSuelo),
              const SizedBox(width: 10),
              _botonVista('3D', _vista3D, () => setState(() => _vista3D = true)),
              const SizedBox(width: 6),
              _botonVista('2D', !_vista3D, () => setState(() => _vista3D = false)),
            ],
          ),
          const SizedBox(height: 12),

          if (_errorSuelo != null && !_cargandoSuelo) ...[
            _avisoError('No se pudo consultar la API de suelo: $_errorSuelo. Se muestran los últimos datos guardados.', _cargarSuelo),
            const SizedBox(height: 12),
          ],

          // Dibujo + panel "Perfil del suelo" (el panel se oculta si no cabe)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final conPanel = constraints.maxWidth >= 620;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: SizedBox.expand(child: CustomPaint(painter: _painterActual(_zoom)))),
                    if (conPanel) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 175,
                        child: _panelLateral(
                          'PERFIL DEL SUELO',
                          [
                            for (final capa in capasSuelo) _buildSoilLayer(capa.nombre, capa.rango(_p.profundidad), capa.color),
                            if (_suelo != null) ...[
                              const SizedBox(height: 6),
                              const Text('COMPOSICIÓN (SUPERFICIE)',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 8),
                              _barraComposicion('Arcilla', _suelo!.arcilla, const Color(0xFF8D6E63)),
                              _barraComposicion('Limo', _suelo!.limo, const Color(0xFFBC8A5F)),
                              _barraComposicion('Arena', _suelo!.arena, const Color(0xFFE2C799)),
                              const SizedBox(height: 4),
                              Text('Textura: ${_suelo!.textura}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Marca.deepBlue)),
                            ],
                          ],
                          _suelo != null
                              ? 'Composición: OpenLandMap vía Google Earth Engine.'
                              : 'Representación esquemática del perfil edáfico.',
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Datos del terreno + controles de zoom
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 20,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(_coordenadasTexto, style: _gris),
                      ],
                    ),
                    Text('Terreno: ${formatoNumero(_p.ancho)} × ${formatoNumero(_p.largo)} m', style: _gris),
                    Text('Profundidad: ${_p.profundidad.toStringAsFixed(2).replaceAll('.', ',')} m', style: _gris),
                    if (_suelo?.elevacion != null) Text('Elevación: ${formatoNumero(_suelo!.elevacion!)} m', style: _gris),
                    if (_suelo?.pendiente != null) Text('Pendiente: ${formatoNumero(_suelo!.pendiente!)}°', style: _gris),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!compacto) ...[
                const Text('• Modelo de referencia', style: _gris),
                const SizedBox(width: 12),
              ],
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _botonControl(Icons.refresh, 'Restablecer', () => setState(() => _zoom = 1.0)),
                    _botonControl(Icons.remove, 'Alejar', () => _cambiarZoom(-0.15)),
                    _botonControl(Icons.add, 'Acercar', () => _cambiarZoom(0.15)),
                    _botonControl(Icons.fullscreen, 'Pantalla completa', _pantallaCompleta),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- TARJETA: CLIMA (datos reales de Meteomatics) ----------------

  // Texto de un valor con sus decimales y unidad, o "—" si todavía no hay dato
  String _valor(double? v, int decimales, String unidad) => v == null ? '—' : '${v.toStringAsFixed(decimales)} $unidad';

  // Texto pequeño de las tarjetas mientras no hay dato
  String get _estadoCarga => _cargandoClima ? 'Consultando...' : (_errorClima != null ? 'Sin conexión' : 'Sin dato');

  String _hora(DateTime? f) => f == null ? '—' : '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

  Widget _tarjetaClima(bool compacto) {
    const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    final hoy = DateTime.now();
    final nombreDia = dias[hoy.weekday - 1];
    final fecha = '${hoy.day} de ${meses[hoy.month - 1]} de ${hoy.year}';
    final clima = _clima;

    return Container(
      padding: EdgeInsets.all(compacto ? 14 : 20),
      decoration: _decoracionTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _encabezadoTarjeta(
                  Icons.wb_sunny_outlined,
                  'PRONÓSTICO DEL DÍA  /  ${_p.nombre.toUpperCase()}',
                  '• CONDICIONES DE HOY  ·  fuente: Meteomatics',
                ),
              ),
              const SizedBox(width: 12),
              // Botón para volver a consultar
              _cargandoClima
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _acento),
                    )
                  : _botonFlecha(Icons.refresh, 'Actualizar ahora', _actualizarAhora),
            ],
          ),
          const SizedBox(height: 12),

          // Aviso si no se pudo conectar
          if (_errorClima != null && !_cargandoClima) ...[
            _avisoErrorClima(),
            const SizedBox(height: 12),
          ],

          // Día + ilustración, y panel "Detalle del día" (se oculta si no cabe)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final conPanel = constraints.maxWidth >= 620;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _climaCentro(nombreDia, fecha)),
                    if (conPanel) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 175,
                        child: _panelLateral(
                          'DETALLE DEL DÍA',
                          [
                            _filaDetalle(Icons.umbrella_outlined, 'Precipitación', '${_valor(clima?.precipitacion, 1, 'mm')} (última hora)', Marca.blueYonder),
                            _filaDetalle(Icons.air, 'Viento', _valor(clima?.viento, 0, 'km/h'), const Color(0xFF7A8CA3)),
                            _filaDetalle(Icons.wb_sunny_outlined, 'Índice UV',
                                clima?.uv == null ? '—' : '${clima!.uv!.round()} · ${nivelUV(clima!.uv!)}', const Color(0xFFF5A623)),
                            _filaDetalle(Icons.wb_twilight, 'Amanecer', _hora(clima?.amanecer), const Color(0xFFE9A23B)),
                            _filaDetalle(Icons.nights_stay_outlined, 'Atardecer', _hora(clima?.atardecer), const Color(0xFF5B5F97)),
                          ],
                          'Datos de Meteomatics para las coordenadas de tu parcela.',
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Ubicación y hora de actualización
          Wrap(
            spacing: 20,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(_coordenadasTexto, style: _gris),
                ],
              ),
              Text(
                _cargandoClima
                    ? 'Consultando clima...'
                    : clima == null
                        ? 'Sin datos todavía'
                        : 'Actualizado: ${_hora(clima.consultado)}  ·  se actualiza cada ${_intervaloActualizacion.inMinutes} min',
                style: _gris,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Franja de aviso cuando falla la conexión
  Widget _avisoErrorClima() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Marca.rojoSuave,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Marca.rojoBorde),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 16, color: Marca.rocketRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No se pudo obtener el clima: $_errorClima',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Marca.martianRed),
            ),
          ),
          TextButton(
            onPressed: _actualizarAhora,
            style: TextButton.styleFrom(foregroundColor: Marca.martianRed),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // Centro del clima: se adapta al alto disponible
  Widget _climaCentro(String nombreDia, String fecha) {
    final clima = _clima;
    final noche = esDeNoche(clima); // De noche cambia el dibujo y los textos
    final cielo = clima == null ? null : estadoCielo(clima, noche: noche);
    final textoCielo = cielo?.texto ?? (_cargandoClima ? 'Consultando...' : '—');
    final iconoCielo = cielo?.icono ?? Icons.cloud_queue;
    final colorCielo = cielo?.color ?? Colors.grey;
    final maxima = clima?.maxima == null ? '—' : '${clima!.maxima!.round()}°';
    final minima = clima?.minima == null ? '—' : '${clima!.minima!.round()}°';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Si hay muy poco alto, versión resumida en una sola línea
        if (constraints.maxHeight < 200) {
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoCielo, size: 36, color: colorCielo),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(nombreDia, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _tinta)),
                      Text('$textoCielo  ·  Máx $maxima / Mín $minima', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        // Versión completa
        return Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(nombreDia, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: _tinta)),
            ),
            const SizedBox(height: 2),
            Text(fecha, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CustomPaint(
                      painter: EscenaSoleadaPainter(
                        nubes: cielo?.nubes ?? false,
                        lluvia: cielo?.lluvia ?? false,
                        noche: noche,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoCielo, size: 22, color: colorCielo),
                  const SizedBox(width: 8),
                  Text(textoCielo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black87)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Máx $maxima', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    TextSpan(text: '   ·   Mín $minima', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- TARJETA: CULTIVAR (solo visual) ----------------
  Widget _tarjetaCultivar(bool compacto) {
    return Container(
      padding: EdgeInsets.all(compacto ? 14 : 20),
      decoration: _decoracionTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _encabezadoTarjeta(
                  Icons.grass_outlined,
                  'CATÁLOGO DE CULTIVOS  /  ${_p.nombre.toUpperCase()}',
                  _errorFichas != null
                      ? '• No se pudo leer el archivo de cultivos  ·  toca ⟳ para reintentar'
                      : '• Arrastra o desliza para explorar  ·  toca "ⓘ" para ver la ficha completa',
                ),
              ),
              const SizedBox(width: 12),
              if (!compacto) ...[
                TextButton.icon(
                  onPressed: () => setState(() => _selectedIndex = 3),
                  icon: const Icon(Icons.show_chart, size: 16),
                  label: const Text('Ver proyección', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _acento),
                ),
                const SizedBox(width: 8),
              ],
              _cargandoFichas
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _acento))
                  : _botonFlecha(Icons.refresh, 'Volver a leer el archivo', _cargarFichas),
              const SizedBox(width: 6),
              _botonFlecha(Icons.chevron_left, 'Anterior', () => _moverCultivos(-1)),
              const SizedBox(width: 6),
              _botonFlecha(Icons.chevron_right, 'Siguiente', () => _moverCultivos(1)),
            ],
          ),
          const SizedBox(height: 14),

          // Fila de tarjetas que se puede arrastrar con el mouse o el dedo
          Expanded(
            child: Listener(
              // La rueda del mouse también mueve la fila hacia los lados
              onPointerSignal: (evento) {
                if (evento is PointerScrollEvent && _cultivosScroll.hasClients) {
                  final posicion = _cultivosScroll.position;
                  final delta = evento.scrollDelta.dx != 0 ? evento.scrollDelta.dx : evento.scrollDelta.dy;
                  _cultivosScroll.jumpTo(
                    (posicion.pixels + delta).clamp(posicion.minScrollExtent, posicion.maxScrollExtent),
                  );
                }
              },
              child: ScrollConfiguration(
                behavior: const ArrastreConMouse(),
                child: RawScrollbar(
                  controller: _cultivosScroll,
                  thumbVisibility: true,
                  trackVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.top,
                  thickness: 6,
                  radius: const Radius.circular(6),
                  trackRadius: const Radius.circular(6),
                  thumbColor: Marca.blueYonder,
                  trackColor: Marca.azulSuave,
                  trackBorderColor: Colors.transparent,
                  child: ShaderMask(
                    // Desvanece suavemente las orillas izquierda y derecha
                    shaderCallback: (rect) => const LinearGradient(
                      colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                      stops: [0, 0.03, 0.97, 1],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: ListView.separated(
                      controller: _cultivosScroll,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 22, 10, 6),
                      itemCount: cultivos.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 14),
                      itemBuilder: (context, index) => TarjetaCultivo(
                        cultivo: cultivos[index],
                        seleccionado: index == _cultivoSeleccionado,
                        dato: _datoCorto(cultivos[index].nombre),
                        onTap: () => setState(() => _cultivoSeleccionado = index),
                        onInfo: () {
                          setState(() => _cultivoSeleccionado = index);
                          _verFicha(cultivos[index]);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- TARJETA: PROYECCIÓN (solo visual) ----------------

  // Valores de ejemplo de la sección Clima (los mismos que se muestran ahí)
  double get _temperaturaHoy => _clima?.temperatura ?? 28; // Real si ya llegó del servidor
  static const double _evaporacionDia = 5.2;

  bool _enRango(double valor, double minimo, double maximo) => valor >= minimo && valor <= maximo;

  // Cuántas de las 4 condiciones ideales cumple la parcela para este cultivo
  int _condicionesCumplidas(Cultivo c) {
    int total = 0;
    if (_enRango(_p.ph, c.phMin, c.phMax)) total++;
    if (_enRango(_temperaturaHoy, c.tempMin, c.tempMax)) total++;
    if (_enRango(_p.humedad, c.humMin, c.humMax)) total++;
    if (_p.materiaOrganica >= 2) total++;
    return total;
  }

  String _textoViabilidad(int cumplidas) {
    if (cumplidas == 4) return 'Alta';
    if (cumplidas >= 2) return 'Media';
    return 'Baja';
  }

  Widget _tarjetaProyeccion(bool compacto) {
    final cultivo = _cultivoActual;
    final hoy = DateTime.now();
    final cosecha = hoy.add(Duration(days: cultivo.dias));

    return Container(
      padding: EdgeInsets.all(compacto ? 14 : 20),
      decoration: _decoracionTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _encabezadoTarjeta(
                  _vistaRotacion ? Icons.autorenew : Icons.show_chart,
                  _vistaRotacion
                      ? 'ROTACIÓN RECOMENDADA  /  ${_p.nombre.toUpperCase()}'
                      : 'PROYECCIÓN DE COSECHA  /  ${_p.nombre.toUpperCase()}',
                  _vistaRotacion
                      ? '• Simulación Monte Carlo con el clima real de la parcela'
                      : _fichas.containsKey(cultivo.nombre)
                          ? '• Cultivo: ${cultivo.nombre}  ·  rangos del archivo BDPLANS (rendimiento de ejemplo)'
                          : '• Cultivo: ${cultivo.nombre}  ·  datos de referencia de ejemplo',
                ),
              ),
              const SizedBox(width: 12),
              if (!_vistaRotacion && !compacto) ...[
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedIndex = 2),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Cambiar cultivo', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _tinta,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              _botonVista('Cultivo', !_vistaRotacion, () => setState(() => _vistaRotacion = false)),
              const SizedBox(width: 6),
              _botonVista('Rotación', _vistaRotacion, () {
                setState(() => _vistaRotacion = true);
                _simularRotacion(); // Se calcula la primera vez que se abre
              }),
            ],
          ),
          const SizedBox(height: 14),

          if (_vistaRotacion)
            Expanded(child: _contenidoRotacion(compacto))
          else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final conPanel = constraints.maxWidth >= 620;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Línea de tiempo + gráfica de crecimiento
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _lineaDeTiempo(cultivo, hoy, cosecha),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Text('CRECIMIENTO ESPERADO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const Spacer(),
                              Container(width: 10, height: 3, color: cultivo.color),
                              const SizedBox(width: 6),
                              Text('% de desarrollo de ${cultivo.nombre.toLowerCase()}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: SizedBox.expand(
                              child: CustomPaint(
                                painter: CurvaCrecimientoPainter(dias: cultivo.dias, color: cultivo.color),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Panel: condiciones ideales vs. tu parcela
                    if (conPanel) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 190,
                        child: _panelLateral(
                          'CONDICIONES DEL CULTIVO',
                          [
                            _filaCondicion('pH del suelo', '${formatoNumero(cultivo.phMin)} – ${formatoNumero(cultivo.phMax)}',
                                formatoNumero(_p.ph), _enRango(_p.ph, cultivo.phMin, cultivo.phMax)),
                            _filaCondicion('Temperatura', '${formatoNumero(cultivo.tempMin)} – ${formatoNumero(cultivo.tempMax)} °C',
                                '${formatoNumero(_temperaturaHoy)} °C', _enRango(_temperaturaHoy, cultivo.tempMin, cultivo.tempMax)),
                            _filaCondicion('Humedad del suelo', '${formatoNumero(cultivo.humMin)} – ${formatoNumero(cultivo.humMax)} %',
                                '${formatoNumero(_p.humedad)} %', _enRango(_p.humedad, cultivo.humMin, cultivo.humMax)),
                            _filaCondicion('Materia orgánica', 'Mínimo 2 %', '${formatoNumero(_p.materiaOrganica)} %', _p.materiaOrganica >= 2),
                          ],
                          'Compara lo que necesita el cultivo con los datos de Terreno y Clima.',
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- VISTA ROTACIÓN (Monte Carlo) ----------------
  Widget _contenidoRotacion(bool compacto) {
    final r = _rotacionActual;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sin riego / Con riego, 3 / 4 cultivos + botón para volver a simular
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _botonVista('Sin riego', !_rotacionConRiego, () {
                    setState(() => _rotacionConRiego = false);
                    _simularRotacion();
                  }),
                  _botonVista('Con riego', _rotacionConRiego, () {
                    setState(() => _rotacionConRiego = true);
                    _simularRotacion();
                  }),
                  const SizedBox(width: 10),
                  _botonVista('3 cultivos', _largoRotacion == 3, () {
                    setState(() => _largoRotacion = 3);
                    _simularRotacion();
                  }),
                  _botonVista('4 cultivos', _largoRotacion == 4, () {
                    setState(() => _largoRotacion = 4);
                    _simularRotacion();
                  }),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_cargandoRotacion)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _acento)),
                  SizedBox(width: 8),
                  Text('Simulando futuros...', style: _gris),
                ],
              )
            else
              TextButton.icon(
                onPressed: () => _simularRotacion(repetir: true),
                icon: const Icon(Icons.casino_outlined, size: 16),
                label: Text(compacto ? 'Simular' : 'Volver a simular', style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _acento),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_errorRotacion != null && !_cargandoRotacion) ...[
          _avisoError('No se pudo simular: $_errorRotacion', () => _simularRotacion(repetir: true)),
          const SizedBox(height: 12),
        ],

        Expanded(
          child: r == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_cargandoRotacion ? Icons.hourglass_top : Icons.casino_outlined, size: 42, color: Marca.blueYonder),
                      const SizedBox(height: 10),
                      Text(
                        _cargandoRotacion
                            ? 'Probando cientos de rotaciones en 1,000 futuros posibles...\n'
                                '(si es una ubicación nueva, primero se descarga su clima del año: puede tardar)'
                            : 'Presiona "Volver a simular" para buscar la mejor rotación.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tarjetaMejorRotacion(r),
                      const SizedBox(height: 18),
                      const Text('5 OPCIONES DISTINTAS (las mejores que no se repiten entre sí)',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Marca.electricBlue, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      for (int i = 0; i < r.ranking.length && i < 5; i++) _filaRotacion(i + 1, r.ranking[i], compacto),
                      const SizedBox(height: 10),
                      if (r.avisoClima != null) ...[
                        _avisoError('Se usó un clima aproximado: ${r.avisoClima}', () => _simularRotacion(repetir: true)),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        'Clima: ${r.fuenteClima}${r.archivoClima != null ? ' (${r.archivoClima})' : ''}  ·  '
                        'pH ${formatoNumero(_p.ph)}  ·  profundidad ${formatoNumero(_p.profundidad)} m'
                        '${_suelo != null ? '  ·  textura ${_suelo!.textura}  ·  materia orgánica ${formatoNumero(_p.materiaOrganica)} %' : '  ·  (sin datos de la API de suelo)'}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // Recuadro destacado con la mejor rotación
  Widget _tarjetaMejorRotacion(ResultadoRotacion r) {
    final mejor = r.mejor;
    if (mejor == null) {
      return Text(r.mensaje, style: const TextStyle(color: Marca.martianRed));
    }
    return FondoMarca(
      variante: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MEJOR ROTACIÓN',
                style: TextStyle(color: Marca.neonYellow, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: 6),
            Text(mejor.rotacion.join('  →  '), style: Marca.titulo(size: 22, color: Marca.white, peso: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              '${(mejor.exito * 100).toStringAsFixed(1)} % de éxito en ${conMiles(r.simulaciones)} futuros simulados'
              '${_rotacionConRiego ? ' (con riego)' : ' (sin riego)'}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
            // Éxito de cada cultivo de la rotación
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < mejor.rotacion.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${i + 1}. ${mejor.rotacion[i]}  ·  ${(mejor.exitoPorCultivo[i] * 100).toStringAsFixed(0)} %',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Fila del top 5
  Widget _filaRotacion(int lugar, FilaRotacion f, bool compacto) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: lugar == 1 ? Marca.azulSuave : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Marca.borde),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: lugar == 1 ? Marca.neonBlue : Marca.azulSeleccion,
            child: Text('$lugar',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: lugar == 1 ? Colors.white : Marca.deepBlue)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(f.rotacion.join(' → '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Marca.deepBlue)),
          ),
          if (!compacto) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: f.exito,
                  minHeight: 6,
                  backgroundColor: Marca.azulSuave,
                  valueColor: const AlwaysStoppedAnimation(Marca.neonBlue),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text('${(f.exito * 100).toStringAsFixed(1)}%',
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Marca.deepBlue)),
          ),
          if (f.riegoMm != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Text('${conMiles(f.riegoMm!)} L/m²',
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ],
        ],
      ),
    );
  }

  // Barra de etapas del cultivo con fechas
  Widget _lineaDeTiempo(Cultivo cultivo, DateTime hoy, DateTime cosecha) {
    final semanasTotales = (cultivo.dias / 7).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'LÍNEA DE TIEMPO  ·  ${cultivo.dias} días (~$semanasTotales semanas)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Siembra: ${fechaCorta(hoy)}  →  Cosecha: ${fechaCorta(cosecha)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Barra de colores con marcador "Hoy"
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final e in etapasCultivo)
                      Expanded(
                        flex: ((e.hasta - e.desde) * 100).round(),
                        child: Container(color: e.color),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: -4,
              child: Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(color: _tinta, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Nombres de las etapas y semanas
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in etapasCultivo)
              Expanded(
                flex: ((e.hasta - e.desde) * 100).round(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text(
                        'Sem ${(e.desde * semanasTotales).floor() + 1}–${math.max((e.desde * semanasTotales).floor() + 1, (e.hasta * semanasTotales).ceil())}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Fila del panel "Condiciones del cultivo"
  static Widget _filaCondicion(String titulo, String ideal, String actual, bool cumple) {
    final color = cumple ? Marca.neonBlue : Marca.rocketRed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 3, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
                Text('Ideal: $ideal', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                Text('Tu parcela: $actual', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.black54)),
              ],
            ),
          ),
          Icon(cumple ? Icons.check_circle : Icons.warning_amber_rounded, size: 16, color: color),
        ],
      ),
    );
  }

  // Mueve la fila de cultivos con las flechas
  void _moverCultivos(int direccion) {
    if (!_cultivosScroll.hasClients) return;
    final posicion = _cultivosScroll.position;
    final destino = (posicion.pixels + direccion * 370).clamp(posicion.minScrollExtent, posicion.maxScrollExtent);
    _cultivosScroll.animateTo(destino, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  // Botón redondo de flecha
  Widget _botonFlecha(IconData icono, String ayuda, VoidCallback onTap) {
    return Tooltip(
      message: ayuda,
      child: Material(
        color: Colors.white,
        shape: CircleBorder(side: BorderSide(color: Colors.grey.shade300)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icono, size: 18, color: _tinta),
          ),
        ),
      ),
    );
  }

  // Franja de aviso de error con botón "Reintentar"
  Widget _avisoError(String mensaje, VoidCallback reintentar) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Marca.rojoSuave,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Marca.rojoBorde),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 16, color: Marca.rocketRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(mensaje, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Marca.martianRed)),
          ),
          TextButton(
            onPressed: reintentar,
            style: TextButton.styleFrom(foregroundColor: Marca.martianRed),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // Barra horizontal de % (arcilla, limo, arena)
  static Widget _barraComposicion(String nombre, double? porcentaje, Color color) {
    final valor = (porcentaje ?? 0).clamp(0, 100).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(nombre, style: const TextStyle(fontSize: 10, color: Colors.black87))),
              Text('${formatoNumero(valor)} %', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: valor / 100,
              minHeight: 5,
              backgroundColor: Marca.azulSuave,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- WIDGETS AUXILIARES ----------------

  static final _decoracionTarjeta = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Marca.borde),
  );

  // Encabezado pequeño de las tarjetas grandes
  Widget _encabezadoTarjeta(IconData icono, String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, size: 14, color: Marca.neonBlue),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Marca.electricBlue, letterSpacing: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          subtitulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // Panel gris de la derecha ("Perfil del suelo" / "Detalle del día")
  Widget _panelLateral(String titulo, List<Widget> filas, String nota) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            ...filas,
            const SizedBox(height: 8),
            Text(nota, style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // Tarjetas inferiores: en fila si caben, si no en dos columnas
  Widget _filaTarjetas(List<Widget> tarjetas) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const espacio = 16.0;
        // Todas en una fila si cada una tiene al menos 190 px; si no, de 2 en 2
        final porFila = constraints.maxWidth >= tarjetas.length * 190 ? tarjetas.length : 2;
        final anchoTarjeta = ((constraints.maxWidth - espacio * (porFila - 1)) / porFila).floorToDouble();
        return Wrap(
          spacing: espacio,
          runSpacing: 12,
          children: [for (final t in tarjetas) SizedBox(width: anchoTarjeta, child: t)],
        );
      },
    );
  }

  // Botón del selector 3D / 2D
  Widget _botonVista(String texto, bool activo, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? Marca.neonBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: activo ? Marca.neonBlue : Marca.borde),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 11,
            fontWeight: activo ? FontWeight.bold : FontWeight.w600,
            color: activo ? Marca.white : Marca.electricBlue,
          ),
        ),
      ),
    );
  }

  // Botón pequeño de los controles de zoom
  Widget _botonControl(IconData icono, String ayuda, VoidCallback onTap) {
    return Tooltip(
      message: ayuda,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icono, size: 15, color: Colors.grey),
        ),
      ),
    );
  }

  // Fila del panel "Perfil del suelo"
  static Widget _buildSoilLayer(String title, String depth, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Container(width: 3, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
                Text(depth, style: const TextStyle(fontSize: 9, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Fila del panel "Detalle del día"
  static Widget _filaDetalle(IconData icono, String titulo, String valor, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 3, height: 26, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Icon(icono, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
                Text(valor, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Tarjeta de métrica (suelo o clima). El valor se encoge si no cabe.
  static Widget _buildMetricCard(String title, String value, String status, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Marca.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: _acento),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: Marca.titulo(size: 22, peso: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _acento, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ============================================================
// 6. ILUSTRACIÓN DEL CLIMA: ESCENA SOLEADA SOBRE LA PARCELA
// ============================================================
class EscenaSoleadaPainter extends CustomPainter {
  final bool nubes; // Dibuja nubes grandes que tapan el sol (o la luna)
  final bool lluvia; // Dibuja gotas de lluvia
  final bool noche; // Cielo oscuro, luna y estrellas

  const EscenaSoleadaPainter({this.nubes = false, this.lluvia = false, this.noche = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final todo = Offset.zero & size;

    // Cielo (de día azul claro; de noche los azules de la marca)
    canvas.drawRect(
      todo,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: noche
              ? const [Color(0xFF07173F), Color(0xFF0B2A6B), Color(0xFF1E3F7A)]
              : const [Color(0xFFCFE6FA), Color(0xFFEFF7FD), Color(0xFFF9FBF4)],
        ).createShader(todo),
    );

    final centroSol = Offset(w * 0.5, h * 0.40);
    final r = math.min(w, h) * 0.16;

    if (noche) {
      _dibujarNoche(canvas, size, centroSol, r);
    } else {
      _dibujarSol(canvas, centroSol, r);
    }

    // Nubes pequeñas (de noche, más oscuras)
    final colorNubecita = noche ? const Color(0xFF51608A) : Colors.white;
    _nube(canvas, Offset(w * 0.18, h * 0.26), r * 0.55, colorNubecita);
    _nube(canvas, Offset(w * 0.82, h * 0.20), r * 0.45, colorNubecita);

    // Cielo nublado: nubes grandes y grises sobre el sol o la luna
    if (nubes) {
      _nube(canvas, Offset(w * 0.42, h * 0.42), r * 1.25, noche ? const Color(0xFF5B6A8F) : const Color(0xFFE3E8EE));
      _nube(canvas, Offset(w * 0.62, h * 0.36), r * 1.05, noche ? const Color(0xFF4A5779) : const Color(0xFFD5DCE4));
    }

    // Lluvia: líneas inclinadas
    if (lluvia) {
      final gota = Paint()
        ..color = noche ? const Color(0xAA8EC5FF) : const Color(0xAA3B82C4)
        ..strokeWidth = math.max(1.5, r * 0.05)
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 26; i++) {
        final x = w * (0.08 + (i * 0.037) % 0.86);
        final y = h * (0.50 + ((i * 7) % 5) * 0.035);
        canvas.drawLine(Offset(x, y), Offset(x - r * 0.12, y + r * 0.32), gota);
      }
    }

    _dibujarCampo(canvas, size);
  }

  // Sol con resplandor y rayos
  void _dibujarSol(Canvas canvas, Offset centroSol, double r) {
    canvas.drawCircle(centroSol, r * 2.1, Paint()..color = const Color(0x22FFC93C));
    canvas.drawCircle(centroSol, r * 1.55, Paint()..color = const Color(0x33FFC93C));

    final rayo = Paint()
      ..color = const Color(0xFFF7B731)
      ..strokeWidth = math.max(2.5, r * 0.09)
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final angulo = i * math.pi / 6;
      final dir = Offset(math.cos(angulo), math.sin(angulo));
      canvas.drawLine(centroSol + dir * (r * 1.28), centroSol + dir * (r * (i.isEven ? 1.75 : 1.55)), rayo);
    }

    canvas.drawCircle(
      centroSol,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFE07A), Color(0xFFF5A623)],
        ).createShader(Rect.fromCircle(center: centroSol, radius: r)),
    );
  }

  // Luna llena con resplandor, cráteres y estrellas
  void _dibujarNoche(Canvas canvas, Size size, Offset centro, double r) {
    final w = size.width;
    final h = size.height;

    // Estrellas en posiciones fijas (siempre las mismas)
    final azar = math.Random(11);
    for (int i = 0; i < 40; i++) {
      final p = Offset(azar.nextDouble() * w, azar.nextDouble() * h * 0.62);
      final brillo = 0.35 + azar.nextDouble() * 0.6;
      canvas.drawCircle(p, 0.6 + azar.nextDouble() * 1.3, Paint()..color = Colors.white.withValues(alpha: brillo));
    }

    // Resplandor de la luna
    canvas.drawCircle(centro, r * 1.9, Paint()..color = const Color(0x14FFFFFF));
    canvas.drawCircle(centro, r * 1.4, Paint()..color = const Color(0x22EAF1FF));

    // Disco de la luna
    canvas.drawCircle(
      centro,
      r * 0.9,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFFFCEB), Color(0xFFE3DFC4)],
        ).createShader(Rect.fromCircle(center: centro, radius: r * 0.9)),
    );

    // Cráteres
    final crater = Paint()..color = const Color(0x22806F4A);
    canvas.drawCircle(centro + Offset(-r * 0.3, -r * 0.2), r * 0.16, crater);
    canvas.drawCircle(centro + Offset(r * 0.25, r * 0.1), r * 0.22, crater);
    canvas.drawCircle(centro + Offset(-r * 0.1, r * 0.4), r * 0.11, crater);
  }

  // Colinas, parcela con surcos y plantitas (de noche, más oscuras)
  void _dibujarCampo(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Colina del fondo
    final colinaFondo = Path()
      ..moveTo(0, h * 0.72)
      ..quadraticBezierTo(w * 0.25, h * 0.58, w * 0.52, h * 0.70)
      ..quadraticBezierTo(w * 0.78, h * 0.80, w, h * 0.64)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(colinaFondo, Paint()..color = noche ? const Color(0xFF2F4F45) : const Color(0xFFB5D3A2));

    // Parcela (campo verde con surcos)
    final campo = Path()
      ..moveTo(0, h * 0.82)
      ..quadraticBezierTo(w * 0.5, h * 0.74, w, h * 0.82)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(campo, Paint()..color = noche ? const Color(0xFF243F33) : const Color(0xFF8DB37A));

    canvas.save();
    canvas.clipPath(campo);
    final surco = Paint()
      ..color = noche ? const Color(0x33000000) : const Color(0x3336592E)
      ..strokeWidth = 1.4;
    for (int i = -8; i <= 8; i++) {
      final xBase = w * 0.5 + i * w * 0.07;
      canvas.drawLine(Offset(w * 0.5 + i * w * 0.02, h * 0.76), Offset(xBase, h), surco);
    }
    canvas.restore();

    // Pequeñas plantitas
    final tallo = Paint()
      ..color = noche ? const Color(0xFF16291F) : const Color(0xFF2D5A27)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final hoja = Paint()..color = noche ? const Color(0xFF2B4A39) : const Color(0xFF4A7C59);
    for (final fx in [0.30, 0.44, 0.58, 0.72]) {
      final base = Offset(w * fx, h * 0.92);
      canvas.drawLine(base, base - Offset(0, h * 0.06), tallo);
      canvas.drawOval(Rect.fromCenter(center: base - Offset(w * 0.012, h * 0.055), width: w * 0.022, height: h * 0.028), hoja);
      canvas.drawOval(Rect.fromCenter(center: base - Offset(-w * 0.012, h * 0.04), width: w * 0.022, height: h * 0.028), hoja);
    }
  }

  // Nube hecha con varios círculos
  void _nube(Canvas canvas, Offset c, double t, [Color color = Colors.white]) {
    final blanco = Paint()..color = color;
    canvas.drawCircle(c + Offset(-t * 0.9, t * 0.15), t * 0.55, blanco);
    canvas.drawCircle(c, t * 0.75, blanco);
    canvas.drawCircle(c + Offset(t * 0.85, t * 0.2), t * 0.5, blanco);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - t * 1.4, c.dy + t * 0.05, t * 2.8, t * 0.65), Radius.circular(t * 0.4)),
      blanco,
    );
  }

  @override
  bool shouldRepaint(covariant EscenaSoleadaPainter old) =>
      old.nubes != nubes || old.lluvia != lluvia || old.noche != noche;
}

// ============================================================
// 7. SECCIÓN CULTIVAR: DATOS, TARJETAS Y DIBUJOS
// ============================================================

// Cultivo del catálogo.
// Los valores de referencia (días, rendimiento, rangos ideales) son DE EJEMPLO
// para la parte visual; después pueden venir de la API.
class Cultivo {
  final String nombre;
  final String tipo; // "Fruta" o "Verdura"
  final Color color; // Color de fondo suave de la tarjeta
  final int dias; // Días aproximados de siembra a cosecha
  final double rendimiento; // kg por m²
  final double phMin, phMax; // pH ideal del suelo
  final double tempMin, tempMax; // Temperatura ideal (°C)
  final double humMin, humMax; // Humedad ideal del suelo (%)

  const Cultivo(
    this.nombre,
    this.tipo,
    this.color, {
    required this.dias,
    required this.rendimiento,
    required this.phMin,
    required this.phMax,
    required this.tempMin,
    required this.tempMax,
    this.humMin = 20,
    this.humMax = 35,
  });
}

const List<Cultivo> cultivos = [
  Cultivo('Chile', 'Verdura', Color(0xFFD7263D), dias: 90, rendimiento: 2.0, phMin: 6.0, phMax: 7.0, tempMin: 20, tempMax: 30),
  Cultivo('Manzana', 'Fruta', Color(0xFFE0453A), dias: 150, rendimiento: 2.5, phMin: 6.0, phMax: 7.0, tempMin: 15, tempMax: 25),
  Cultivo('Tomate', 'Verdura', Color(0xFFE84B3C), dias: 85, rendimiento: 4.0, phMin: 6.0, phMax: 6.8, tempMin: 20, tempMax: 28),
  Cultivo('Zanahoria', 'Verdura', Color(0xFFF57C1F), dias: 80, rendimiento: 3.0, phMin: 6.0, phMax: 6.8, tempMin: 15, tempMax: 22),
  Cultivo('Maíz', 'Verdura', Color(0xFFF4C430), dias: 110, rendimiento: 0.8, phMin: 5.8, phMax: 7.0, tempMin: 20, tempMax: 30),
  Cultivo('Aguacate', 'Fruta', Color(0xFF558B2F), dias: 240, rendimiento: 1.0, phMin: 5.5, phMax: 6.5, tempMin: 18, tempMax: 28),
  Cultivo('Plátano', 'Fruta', Color(0xFFF7D046), dias: 300, rendimiento: 3.0, phMin: 5.5, phMax: 7.0, tempMin: 24, tempMax: 32, humMin: 25, humMax: 40),
  Cultivo('Naranja', 'Fruta', Color(0xFFF59E2B), dias: 240, rendimiento: 2.5, phMin: 6.0, phMax: 7.5, tempMin: 20, tempMax: 30),
  Cultivo('Limón', 'Fruta', Color(0xFF8BC34A), dias: 200, rendimiento: 2.5, phMin: 5.5, phMax: 6.5, tempMin: 22, tempMax: 32),
  Cultivo('Fresa', 'Fruta', Color(0xFFE53950), dias: 90, rendimiento: 1.5, phMin: 5.5, phMax: 6.5, tempMin: 15, tempMax: 25),
  Cultivo('Sandía', 'Fruta', Color(0xFF2E7D32), dias: 85, rendimiento: 4.0, phMin: 6.0, phMax: 7.0, tempMin: 22, tempMax: 32),
  Cultivo('Uva', 'Fruta', Color(0xFF7E57C2), dias: 150, rendimiento: 1.5, phMin: 6.0, phMax: 7.0, tempMin: 18, tempMax: 28),
  Cultivo('Lechuga', 'Verdura', Color(0xFF66BB6A), dias: 60, rendimiento: 2.5, phMin: 6.0, phMax: 7.0, tempMin: 12, tempMax: 20),
  Cultivo('Cebolla', 'Verdura', Color(0xFFB05A9E), dias: 120, rendimiento: 3.5, phMin: 6.0, phMax: 7.0, tempMin: 13, tempMax: 25),
  Cultivo('Papa', 'Verdura', Color(0xFFC9A26B), dias: 100, rendimiento: 2.5, phMin: 5.0, phMax: 6.5, tempMin: 15, tempMax: 22),
];

// Etapas del cultivo como fracción del ciclo total (0 = siembra, 1 = cosecha)
class EtapaCultivo {
  final String nombre;
  final double desde;
  final double hasta;
  final Color color;
  const EtapaCultivo(this.nombre, this.desde, this.hasta, this.color);
}

const List<EtapaCultivo> etapasCultivo = [
  EtapaCultivo('Siembra', 0.0, 0.08, Marca.deepBlue),
  EtapaCultivo('Germinación', 0.08, 0.22, Marca.blueYonder),
  EtapaCultivo('Crecimiento', 0.22, 0.60, Marca.neonBlue),
  EtapaCultivo('Floración', 0.60, 0.85, Marca.neonYellow),
  EtapaCultivo('Cosecha', 0.85, 1.0, Marca.rocketRed),
];

// 12500 -> "12,500"
String conMiles(num valor) {
  final texto = valor.round().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < texto.length; i++) {
    if (i > 0 && (texto.length - i) % 3 == 0) buffer.write(',');
    buffer.write(texto[i]);
  }
  return buffer.toString();
}

// Fecha corta: "12 feb 2027"
String fechaCorta(DateTime f) {
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${f.day} ${meses[f.month - 1]} ${f.year}';
}

// Permite arrastrar la fila con el mouse (en web normalmente solo se puede con el dedo)
class ArrastreConMouse extends MaterialScrollBehavior {
  const ArrastreConMouse();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  // Usamos nuestra propia barra (la de arriba), así que ocultamos la automática
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// Tarjeta de un cultivo: nombre, dibujo e "info"
class TarjetaCultivo extends StatefulWidget {
  final Cultivo cultivo;
  final bool seleccionado;
  final String dato; // Texto corto del archivo de cultivos (o "info")
  final VoidCallback onTap;
  final VoidCallback onInfo; // Abre la ficha completa

  const TarjetaCultivo({
    super.key,
    required this.cultivo,
    required this.seleccionado,
    required this.dato,
    required this.onTap,
    required this.onInfo,
  });

  @override
  State<TarjetaCultivo> createState() => _TarjetaCultivoState();
}

class _TarjetaCultivoState extends State<TarjetaCultivo> {
  bool _encima = false; // true cuando el mouse está sobre la tarjeta

  @override
  Widget build(BuildContext context) {
    final c = widget.cultivo;
    const verde = Marca.neonBlue;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 170,
          padding: const EdgeInsets.all(12),
          transform: Matrix4.translationValues(0, _encima ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.seleccionado ? verde : Colors.grey.shade200,
              width: widget.seleccionado ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _encima ? 0.10 : 0.04),
                blurRadius: _encima ? 18 : 8,
                offset: Offset(0, _encima ? 8 : 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nombre y tipo
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Marca.deepBlue),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(c.tipo, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.black54)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Dibujo del cultivo
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: CustomPaint(painter: DibujoCultivoPainter(c.nombre)),
                ),
              ),
              const SizedBox(height: 10),

              // Dato corto del archivo; al tocarlo abre la ficha completa
              Material(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onInfo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.dato,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: Colors.black54, height: 1.25),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dibuja cada fruta o verdura en un espacio de 100 x 100 que se escala al tamaño real
class DibujoCultivoPainter extends CustomPainter {
  final String nombre;
  const DibujoCultivoPainter(this.nombre);

  @override
  void paint(Canvas canvas, Size size) {
    final lado = math.min(size.width, size.height);
    if (lado <= 0) return;

    canvas.save();
    canvas.translate((size.width - lado) / 2, (size.height - lado) / 2);
    canvas.scale(lado / 100);

    switch (nombre) {
      case 'Chile':
        _chile(canvas);
        break;
      case 'Manzana':
        _manzana(canvas);
        break;
      case 'Tomate':
        _tomate(canvas);
        break;
      case 'Zanahoria':
        _zanahoria(canvas);
        break;
      case 'Maíz':
        _maiz(canvas);
        break;
      case 'Aguacate':
        _aguacate(canvas);
        break;
      case 'Plátano':
        _platano(canvas);
        break;
      case 'Naranja':
        _naranja(canvas);
        break;
      case 'Limón':
        _limon(canvas);
        break;
      case 'Fresa':
        _fresa(canvas);
        break;
      case 'Sandía':
        _sandia(canvas);
        break;
      case 'Uva':
        _uva(canvas);
        break;
      case 'Lechuga':
        _lechuga(canvas);
        break;
      case 'Cebolla':
        _cebolla(canvas);
        break;
      case 'Papa':
        _papa(canvas);
        break;
    }

    canvas.restore();
  }

  // ---------- Herramientas ----------
  Paint _p(int color) => Paint()..color = Color(color);

  Paint _linea(int color, double grosor) => Paint()
    ..color = Color(color)
    ..strokeWidth = grosor
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  void _hoja(Canvas c, Offset centro, double ancho, double alto, double angulo, [int color = 0xFF4CAF50]) {
    c.save();
    c.translate(centro.dx, centro.dy);
    c.rotate(angulo);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: ancho, height: alto), _p(color));
    c.restore();
  }

  void _tallo(Canvas c, Offset a, Offset b) => c.drawLine(a, b, _linea(0xFF6D4C2F, 3));

  void _brillo(Canvas c, Rect r) => c.drawOval(r, _p(0x55FFFFFF));

  // ---------- Dibujos ----------
  void _manzana(Canvas c) {
    _tallo(c, const Offset(50, 34), const Offset(53, 16));
    _hoja(c, const Offset(63, 20), 18, 9, -0.5);
    final rojo = _p(0xFFE0453A);
    c.drawCircle(const Offset(38, 58), 26, rojo);
    c.drawCircle(const Offset(62, 58), 26, rojo);
    c.drawOval(const Rect.fromLTWH(20, 52, 60, 36), rojo);
    _brillo(c, const Rect.fromLTWH(26, 42, 10, 16));
  }

  void _tomate(Canvas c) {
    c.drawOval(const Rect.fromLTWH(14, 30, 72, 58), _p(0xFFE84B3C));
    _brillo(c, const Rect.fromLTWH(24, 42, 12, 10));
    for (int i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5 - math.pi / 2;
      _hoja(c, Offset(50 + math.cos(a) * 9, 33 + math.sin(a) * 5), 16, 6, a, 0xFF3E8E41);
    }
    c.drawLine(const Offset(50, 32), const Offset(50, 21), _linea(0xFF3E8E41, 3));
  }

  void _naranja(Canvas c) {
    _tallo(c, const Offset(50, 26), const Offset(50, 17));
    _hoja(c, const Offset(60, 20), 16, 8, -0.4);
    c.drawCircle(const Offset(50, 56), 32, _p(0xFFF59E2B));
    for (final o in const [Offset(40, 50), Offset(60, 46), Offset(55, 66), Offset(38, 68), Offset(66, 62), Offset(48, 38)]) {
      c.drawCircle(o, 1.3, _p(0x33B35A00));
    }
    _brillo(c, const Rect.fromLTWH(30, 38, 12, 10));
  }

  void _limon(Canvas c) {
    _hoja(c, const Offset(66, 26), 18, 8, -0.6);
    c.save();
    c.translate(50, 58);
    c.rotate(-0.35);
    final verde = _p(0xFF8BC34A);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 66, height: 46), verde);
    c.drawOval(Rect.fromCenter(center: const Offset(-33, 0), width: 10, height: 8), verde);
    c.drawOval(Rect.fromCenter(center: const Offset(33, 0), width: 10, height: 8), verde);
    _brillo(c, Rect.fromCenter(center: const Offset(-12, -10), width: 16, height: 8));
    c.restore();
  }

  void _chile(Canvas c) {
    final cuerpo = Path()
      ..moveTo(30, 34)
      ..cubicTo(55, 30, 80, 45, 72, 70)
      ..quadraticBezierTo(66, 86, 52, 90);
    c.drawPath(cuerpo, _linea(0xFFD7263D, 15));
    final brillo = Path()
      ..moveTo(38, 31)
      ..cubicTo(55, 30, 70, 40, 69, 56);
    c.drawPath(brillo, _linea(0x66FFFFFF, 3));
    c.drawCircle(const Offset(28, 34), 8, _p(0xFF3E8E41));
    c.drawLine(const Offset(25, 30), const Offset(18, 17), _linea(0xFF3E8E41, 4));
  }

  void _zanahoria(Canvas c) {
    _hoja(c, const Offset(44, 20), 8, 22, -0.4);
    _hoja(c, const Offset(50, 17), 8, 24, 0);
    _hoja(c, const Offset(56, 20), 8, 22, 0.4);
    final cuerpo = Path()
      ..moveTo(35, 30)
      ..lineTo(65, 30)
      ..quadraticBezierTo(63, 62, 50, 92)
      ..quadraticBezierTo(37, 62, 35, 30)
      ..close();
    c.drawPath(cuerpo, _p(0xFFF57C1F));
    final raya = _linea(0x55A04000, 2);
    c.drawLine(const Offset(41, 44), const Offset(49, 44), raya);
    c.drawLine(const Offset(52, 56), const Offset(59, 55), raya);
    c.drawLine(const Offset(44, 70), const Offset(50, 70), raya);
  }

  void _maiz(Canvas c) {
    final hojaIzq = Path()
      ..moveTo(50, 92)
      ..quadraticBezierTo(18, 70, 28, 30)
      ..quadraticBezierTo(40, 62, 50, 92)
      ..close();
    final hojaDer = Path()
      ..moveTo(50, 92)
      ..quadraticBezierTo(82, 70, 72, 30)
      ..quadraticBezierTo(60, 62, 50, 92)
      ..close();
    c.drawPath(hojaIzq, _p(0xFF7CB342));
    c.drawPath(hojaDer, _p(0xFF7CB342));
    c.drawOval(const Rect.fromLTWH(36, 14, 28, 70), _p(0xFFF4C430));
    for (double y = 21; y <= 76; y += 7) {
      for (final x in const [43.0, 50.0, 57.0]) {
        c.drawCircle(Offset(x, y), 2.4, _p(0xFFE0A800));
      }
    }
    final frenteIzq = Path()
      ..moveTo(50, 94)
      ..quadraticBezierTo(30, 80, 33, 52)
      ..quadraticBezierTo(44, 74, 50, 94)
      ..close();
    final frenteDer = Path()
      ..moveTo(50, 94)
      ..quadraticBezierTo(70, 80, 67, 52)
      ..quadraticBezierTo(56, 74, 50, 94)
      ..close();
    c.drawPath(frenteIzq, _p(0xFF8BC34A));
    c.drawPath(frenteDer, _p(0xFF9CCC65));
  }

  void _aguacate(Canvas c) {
    final cascara = _p(0xFF3E6B2E);
    c.drawCircle(const Offset(50, 62), 28, cascara);
    c.drawCircle(const Offset(50, 36), 18, cascara);
    final pulpa = _p(0xFFD4E79E);
    c.drawCircle(const Offset(50, 62), 22, pulpa);
    c.drawCircle(const Offset(50, 40), 13, pulpa);
    c.drawCircle(const Offset(50, 62), 12, _p(0xFF8D5A2B));
    _brillo(c, const Rect.fromLTWH(44, 55, 6, 6));
  }

  void _platano(Canvas c) {
    const centro = Offset(50, 22);
    const radio = 44.0;
    const inicio = 0.55;
    const recorrido = 2.05;
    final rect = Rect.fromCircle(center: centro, radius: radio);
    c.drawArc(rect, inicio, recorrido, false, _linea(0xFFF7D046, 18));
    c.drawArc(Rect.fromCircle(center: centro, radius: radio - 6), inicio + 0.1, recorrido - 0.2, false, _linea(0x33A07000, 3));
    final puntaA = centro + Offset(math.cos(inicio), math.sin(inicio)) * radio;
    final puntaB = centro + Offset(math.cos(inicio + recorrido), math.sin(inicio + recorrido)) * radio;
    c.drawCircle(puntaA, 4, _p(0xFF5D4037));
    c.drawLine(puntaB, puntaB + const Offset(-4, -9), _linea(0xFF6D4C2F, 5));
  }

  void _fresa(Canvas c) {
    final cuerpo = Path()
      ..moveTo(50, 90)
      ..quadraticBezierTo(16, 62, 24, 38)
      ..quadraticBezierTo(50, 26, 76, 38)
      ..quadraticBezierTo(84, 62, 50, 90)
      ..close();
    c.drawPath(cuerpo, _p(0xFFE53950));
    for (final o in const [
      Offset(36, 46), Offset(50, 44), Offset(64, 46), Offset(42, 58),
      Offset(58, 58), Offset(50, 70), Offset(36, 62), Offset(64, 62), Offset(50, 56)
    ]) {
      c.drawOval(Rect.fromCenter(center: o, width: 2.6, height: 3.6), _p(0xFFFFE082));
    }
    for (int i = 0; i < 5; i++) {
      final a = math.pi + i * math.pi / 4;
      _hoja(c, Offset(50 + math.cos(a) * 10, 34 + math.sin(a) * 4), 16, 7, a, 0xFF3E8E41);
    }
    c.drawLine(const Offset(50, 32), const Offset(51, 20), _linea(0xFF3E8E41, 3));
  }

  void _sandia(Canvas c) {
    const centro = Offset(50, 36);
    c.drawArc(Rect.fromCircle(center: centro, radius: 44), 0, math.pi, true, _p(0xFF2E7D32));
    c.drawArc(Rect.fromCircle(center: centro, radius: 38), 0, math.pi, true, _p(0xFFC5E1A5));
    c.drawArc(Rect.fromCircle(center: centro, radius: 34), 0, math.pi, true, _p(0xFFEF4F5F));
    for (final o in const [Offset(34, 46), Offset(50, 52), Offset(66, 46), Offset(42, 60), Offset(58, 60), Offset(50, 40)]) {
      c.drawOval(Rect.fromCenter(center: o, width: 3, height: 5), _p(0xFF222222));
    }
  }

  void _uva(Canvas c) {
    _tallo(c, const Offset(50, 30), const Offset(52, 14));
    _hoja(c, const Offset(64, 18), 20, 11, -0.4);
    const filas = [
      [Offset(36, 36), Offset(50, 36), Offset(64, 36)],
      [Offset(29, 49), Offset(43, 49), Offset(57, 49), Offset(71, 49)],
      [Offset(36, 62), Offset(50, 62), Offset(64, 62)],
      [Offset(43, 75), Offset(57, 75)],
      [Offset(50, 88)],
    ];
    for (final fila in filas) {
      for (final o in fila) {
        c.drawCircle(o, 8, _p(0xFF7E57C2));
        c.drawCircle(o + const Offset(-2.5, -2.5), 2, _p(0x66FFFFFF));
      }
    }
  }

  void _lechuga(Canvas c) {
    const centro = Offset(50, 55);
    c.drawCircle(centro, 36, _p(0xFF66BB6A));
    c.drawCircle(centro, 27, _p(0xFF81C784));
    c.drawCircle(centro, 18, _p(0xFFA5D6A7));
    c.drawCircle(centro, 9, _p(0xFFC8E6C9));
    final vena = _linea(0x332E7D32, 2);
    for (int i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      c.drawLine(centro + Offset(math.cos(a), math.sin(a)) * 10, centro + Offset(math.cos(a), math.sin(a)) * 34, vena);
    }
  }

  void _cebolla(Canvas c) {
    c.drawLine(const Offset(50, 24), const Offset(45, 8), _linea(0xFF4CAF50, 3));
    c.drawLine(const Offset(50, 24), const Offset(56, 10), _linea(0xFF4CAF50, 3));
    final cuerpo = Path()
      ..moveTo(50, 22)
      ..quadraticBezierTo(52, 34, 70, 46)
      ..quadraticBezierTo(86, 62, 70, 80)
      ..quadraticBezierTo(50, 94, 30, 80)
      ..quadraticBezierTo(14, 62, 30, 46)
      ..quadraticBezierTo(48, 34, 50, 22)
      ..close();
    c.drawPath(cuerpo, _p(0xFFB05A9E));
    final raya = _linea(0x44FFFFFF, 2);
    c.drawPath(Path()..moveTo(50, 28)..quadraticBezierTo(36, 56, 44, 86), raya);
    c.drawPath(Path()..moveTo(50, 28)..quadraticBezierTo(64, 56, 56, 86), raya);
    final raiz = _linea(0xFFD7CCC8, 2);
    c.drawLine(const Offset(50, 88), const Offset(45, 95), raiz);
    c.drawLine(const Offset(50, 88), const Offset(50, 96), raiz);
    c.drawLine(const Offset(50, 88), const Offset(55, 95), raiz);
  }

  void _papa(Canvas c) {
    final cuerpo = Path()
      ..moveTo(20, 54)
      ..quadraticBezierTo(18, 30, 48, 32)
      ..quadraticBezierTo(76, 26, 84, 50)
      ..quadraticBezierTo(90, 74, 60, 78)
      ..quadraticBezierTo(28, 86, 20, 54)
      ..close();
    c.drawPath(cuerpo, _p(0xFFC9A26B));
    for (final o in const [Offset(38, 48), Offset(62, 44), Offset(56, 64), Offset(34, 66), Offset(72, 58)]) {
      c.drawOval(Rect.fromCenter(center: o, width: 5, height: 3.5), _p(0xFF9E7A4A));
    }
    _brillo(c, const Rect.fromLTWH(30, 38, 14, 7));
  }

  @override
  bool shouldRepaint(covariant DibujoCultivoPainter old) => old.nombre != nombre;
}

// ============================================================
// 8. PROYECCIÓN: CURVA DE CRECIMIENTO DEL CULTIVO
// ============================================================
class CurvaCrecimientoPainter extends CustomPainter {
  final int dias;
  final Color color;

  const CurvaCrecimientoPainter({required this.dias, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 80 || size.height < 50) return;
    canvas.clipRect(Offset.zero & size);

    const gris = Color(0xFF9A9A9A);
    const izquierda = 34.0; // espacio para etiquetas de %
    const abajo = 20.0; // espacio para etiquetas de días
    const arriba = 10.0;
    final derecha = size.width - 12;
    final base = size.height - abajo;
    final alto = base - arriba;
    final ancho = derecha - izquierda;

    // Líneas guía punteadas y etiquetas de %
    final guia = Paint()
      ..color = const Color(0xFFE5EAF0)
      ..strokeWidth = 1;
    for (final f in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final y = base - alto * f;
      for (double x = izquierda; x < derecha; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, derecha), y), guia);
      }
      dibujarTexto(canvas, '${(f * 100).round()}%', Offset(izquierda - 18, y), size: 9, color: gris, weight: FontWeight.w400);
    }

    // Separadores verticales de cada etapa
    final separador = Paint()
      ..color = const Color(0xFFEDEDED)
      ..strokeWidth = 1;
    for (final e in etapasCultivo.skip(1)) {
      final x = izquierda + ancho * e.desde;
      canvas.drawLine(Offset(x, arriba), Offset(x, base), separador);
    }

    // Curva en forma de "S" (crecimiento logístico)
    double crecimiento(double t) {
      final v = 1 / (1 + math.exp(-10 * (t - 0.45)));
      final v0 = 1 / (1 + math.exp(4.5));
      final v1 = 1 / (1 + math.exp(-5.5));
      return (v - v0) / (v1 - v0);
    }

    final curva = Path();
    for (int i = 0; i <= 60; i++) {
      final t = i / 60;
      final punto = Offset(izquierda + ancho * t, base - alto * crecimiento(t));
      if (i == 0) {
        curva.moveTo(punto.dx, punto.dy);
      } else {
        curva.lineTo(punto.dx, punto.dy);
      }
    }

    // Relleno degradado
    final relleno = Path.from(curva)
      ..lineTo(derecha, base)
      ..lineTo(izquierda, base)
      ..close();
    canvas.drawPath(
      relleno,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTRB(izquierda, arriba, derecha, base)),
    );

    // Línea
    canvas.drawPath(
      curva,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );

    // Eje inferior
    canvas.drawLine(Offset(izquierda, base), Offset(derecha, base), Paint()..color = const Color(0xFFD0D5DB));

    // Marcador "Hoy" (inicio) y "Cosecha" (final)
    final inicio = Offset(izquierda, base - alto * crecimiento(0));
    final fin = Offset(derecha, base - alto * crecimiento(1));
    canvas.drawCircle(inicio, 5, Paint()..color = Marca.deepBlue);
    canvas.drawCircle(fin, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      fin,
      7,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    dibujarTexto(canvas, 'Hoy', inicio + const Offset(16, -10), size: 9, color: Marca.deepBlue);
    dibujarTexto(canvas, 'Cosecha', fin + const Offset(-26, 14), size: 9, color: color);

    // Etiquetas de días
    for (final f in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final x = izquierda + ancho * f;
      dibujarTexto(canvas, 'Día ${(dias * f).round()}', Offset(x, base + 11), size: 9, color: gris, weight: FontWeight.w400);
    }
  }

  @override
  bool shouldRepaint(covariant CurvaCrecimientoPainter old) => old.dias != dias || old.color != color;
}

// ============================================================
// 9. CONEXIÓN CON EL SERVIDOR DE CLIMA (Python + Meteomatics)
// ============================================================

// Dirección del servidor Python (servidor_clima.py).
// - Web y Windows: http://localhost:5000
// - Emulador de Android: http://10.0.2.2:5000
// - Celular real: la IP de tu computadora, por ejemplo http://192.168.1.50:5000
const String kServidorClima = 'http://localhost:5000';

// Datos del clima tal como los regresa el servidor
class DatosClima {
  final double? temperatura; // °C
  final double? humedad; // % humedad relativa del aire
  final double? precipitacion; // mm en la última hora
  final double? evaporacion; // mm en la última hora (evapotranspiración)
  final double? radiacion; // W/m² (cielo despejado)
  final double? uv; // índice UV
  final double? maxima; // °C máxima de 24 h
  final double? minima; // °C mínima de 24 h
  final double? viento; // km/h
  final int? simbolo; // símbolo del clima de Meteomatics
  final DateTime? amanecer;
  final DateTime? atardecer;
  final DateTime consultado;

  const DatosClima({
    this.temperatura,
    this.humedad,
    this.precipitacion,
    this.evaporacion,
    this.radiacion,
    this.uv,
    this.maxima,
    this.minima,
    this.viento,
    this.simbolo,
    this.amanecer,
    this.atardecer,
    required this.consultado,
  });

  factory DatosClima.fromJson(Map<String, dynamic> json) {
    double? numero(String clave) => (json[clave] as num?)?.toDouble();
    DateTime? fecha(String clave) {
      final valor = json[clave];
      return valor is String ? DateTime.tryParse(valor)?.toLocal() : null;
    }

    return DatosClima(
      temperatura: numero('temperatura'),
      humedad: numero('humedad'),
      precipitacion: numero('precipitacion'),
      evaporacion: numero('evaporacion'),
      radiacion: numero('radiacion'),
      uv: numero('uv'),
      maxima: numero('maxima'),
      minima: numero('minima'),
      viento: numero('viento'),
      simbolo: numero('simbolo')?.round(),
      amanecer: fecha('amanecer'),
      atardecer: fecha('atardecer'),
      consultado: fecha('consultado') ?? DateTime.now(),
    );
  }
}

class ClimaService {
  static Future<DatosClima> obtener(double latitud, double longitud, {bool forzar = false}) async {
    final uri = Uri.parse('$kServidorClima/api/clima').replace(queryParameters: {
      'lat': latitud.toString(),
      'lon': longitud.toString(),
      if (forzar) 'forzar': '1',
    });

    final http.Response respuesta;
    try {
      respuesta = await http.get(uri).timeout(const Duration(seconds: 40));
    } catch (_) {
      throw Exception('el servidor de clima no responde. ¿Está corriendo servidor_clima.py?');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(respuesta.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('respuesta inválida del servidor (${respuesta.statusCode})');
    }

    if (respuesta.statusCode != 200) {
      throw Exception(json['error'] ?? 'error ${respuesta.statusCode}');
    }
    return DatosClima.fromJson(json);
  }
}

// Cómo se ve el cielo: texto, ícono y cómo dibujar la ilustración
class EstadoCielo {
  final String texto;
  final IconData icono;
  final Color color;
  final bool nubes;
  final bool lluvia;
  final bool noche;
  const EstadoCielo(this.texto, this.icono, this.color, {this.nubes = false, this.lluvia = false, this.noche = false});
}

// ¿Es de noche ahora? Se usa la hora real de amanecer y atardecer de la parcela.
// Si no llegaron, se usa el símbolo de Meteomatics (los de noche son > 100) o la hora.
bool esDeNoche(DatosClima? d) {
  final ahora = DateTime.now();
  final minutos = ahora.hour * 60 + ahora.minute;
  final amanecer = d?.amanecer;
  final atardecer = d?.atardecer;
  if (amanecer != null && atardecer != null) {
    final mAmanecer = amanecer.hour * 60 + amanecer.minute;
    final mAtardecer = atardecer.hour * 60 + atardecer.minute;
    return minutos < mAmanecer || minutos >= mAtardecer;
  }
  if (d?.simbolo != null) return d!.simbolo! > 100;
  return ahora.hour < 6 || ahora.hour >= 19;
}

EstadoCielo estadoCielo(DatosClima d, {bool noche = false}) {
  const sol = Color(0xFFF5A623);
  const luna = Color(0xFF5B5F97);
  const nube = Color(0xFF7A8CA3);
  const azul = Marca.blueYonder;
  const tormenta = Color(0xFF5B5F97);

  var simbolo = d.simbolo;
  if (simbolo != null && simbolo > 100) {
    simbolo -= 100; // Meteomatics suma 100 a los símbolos de noche
  }

  // Símbolos de Meteomatics: 1 despejado, 2 pocas nubes, 3 parcialmente nublado, 4 nublado...
  switch (simbolo) {
    case 1:
      return noche
          ? const EstadoCielo('Despejado', Icons.nights_stay_outlined, luna, noche: true)
          : const EstadoCielo('Soleado', Icons.wb_sunny, sol);
    case 2:
      // Pocas nubes: se dibujan solo las nubecitas, sin tapar el sol o la luna
      return noche
          ? const EstadoCielo('Pocas nubes', Icons.nights_stay_outlined, luna, noche: true)
          : const EstadoCielo('Mayormente soleado', Icons.wb_sunny_outlined, sol);
    case 3:
      return EstadoCielo('Parcialmente nublado', Icons.wb_cloudy_outlined, nube, nubes: true, noche: noche);
    case 4:
      return EstadoCielo('Nublado', Icons.cloud_outlined, nube, nubes: true, noche: noche);
    case 5:
    case 8:
    case 15:
      return EstadoCielo('Lluvia', Icons.umbrella_outlined, azul, nubes: true, lluvia: true, noche: noche);
    case 6:
    case 7:
    case 9:
    case 10:
    case 13:
      return EstadoCielo('Nieve o aguanieve', Icons.ac_unit, azul, nubes: true, lluvia: true, noche: noche);
    case 11:
    case 12:
      return EstadoCielo('Niebla', Icons.foggy, nube, nubes: true, noche: noche);
    case 14:
      return EstadoCielo('Tormenta', Icons.thunderstorm_outlined, tormenta, nubes: true, lluvia: true, noche: noche);
    case 16:
      return EstadoCielo('Tormenta de arena', Icons.air, nube, nubes: true, noche: noche);
  }

  // Si no llegó el símbolo, se estima con la lluvia de la última hora
  if ((d.precipitacion ?? 0) > 0.1) {
    return EstadoCielo('Lluvia', Icons.umbrella_outlined, azul, nubes: true, lluvia: true, noche: noche);
  }
  if (noche) {
    return const EstadoCielo('Despejado', Icons.nights_stay_outlined, luna, noche: true);
  }
  return const EstadoCielo('Soleado', Icons.wb_sunny, sol);
}

// Textos de nivel para las tarjetas
String nivelRadiacion(double v) => v < 200 ? 'Radiación baja' : (v < 600 ? 'Radiación moderada' : 'Radiación alta');
String nivelHumedadAire(double v) => v < 30 ? 'Aire seco' : (v <= 70 ? 'Nivel normal' : 'Muy húmedo');
String nivelTemperatura(double v) => v < 10 ? 'Frío' : (v <= 30 ? 'Templado' : 'Caluroso');
String nivelEvaporacion(double v) => v < 0.1 ? 'Evaporación baja' : (v < 0.4 ? 'Evaporación moderada' : 'Evaporación alta');
String nivelUV(double v) {
  if (v < 3) return 'Bajo';
  if (v < 6) return 'Moderado';
  if (v < 8) return 'Alto';
  if (v < 11) return 'Muy alto';
  return 'Extremo';
}

// ============================================================
// 10. CULTIVOS: DATOS DEL ARCHIVO BDPLANS_cultivos.csv (vía servidor)
// ============================================================

// Todos los campos del archivo para un cultivo
class FichaCultivo {
  final String? cientifico, nombresComunes, grupo, formaVida, cicloVida;
  final double? tempMinAbs, tempMinOpt, tempMaxOpt, tempMaxAbs, tempLetal;
  final double? lluviaMinAbs, lluviaMinOpt, lluviaMaxOpt, lluviaMaxAbs;
  final double? phMinAbs, phMinOpt, phMaxOpt, phMaxAbs;
  final double? cicloMin, cicloMax, altitudMax;
  final String? texturaOpt, texturaTol, drenajeOpt, drenajeTol;
  final String? fertilidadOpt, fertilidadTol, salinidadOpt, salinidadTol;
  final String? profundidadOpt, profundidadTol;

  const FichaCultivo({
    this.cientifico,
    this.nombresComunes,
    this.grupo,
    this.formaVida,
    this.cicloVida,
    this.tempMinAbs,
    this.tempMinOpt,
    this.tempMaxOpt,
    this.tempMaxAbs,
    this.tempLetal,
    this.lluviaMinAbs,
    this.lluviaMinOpt,
    this.lluviaMaxOpt,
    this.lluviaMaxAbs,
    this.phMinAbs,
    this.phMinOpt,
    this.phMaxOpt,
    this.phMaxAbs,
    this.cicloMin,
    this.cicloMax,
    this.altitudMax,
    this.texturaOpt,
    this.texturaTol,
    this.drenajeOpt,
    this.drenajeTol,
    this.fertilidadOpt,
    this.fertilidadTol,
    this.salinidadOpt,
    this.salinidadTol,
    this.profundidadOpt,
    this.profundidadTol,
  });

  factory FichaCultivo.fromJson(Map<String, dynamic> j) {
    double? n(String k) => (j[k] as num?)?.toDouble();
    String? t(String k) => j[k] as String?;
    return FichaCultivo(
      cientifico: t('cientifico'),
      nombresComunes: t('nombresComunes'),
      grupo: t('grupo'),
      formaVida: t('formaVida'),
      cicloVida: t('cicloVida'),
      tempMinAbs: n('tempMinAbs'),
      tempMinOpt: n('tempMinOpt'),
      tempMaxOpt: n('tempMaxOpt'),
      tempMaxAbs: n('tempMaxAbs'),
      tempLetal: n('tempLetal'),
      lluviaMinAbs: n('lluviaMinAbs'),
      lluviaMinOpt: n('lluviaMinOpt'),
      lluviaMaxOpt: n('lluviaMaxOpt'),
      lluviaMaxAbs: n('lluviaMaxAbs'),
      phMinAbs: n('phMinAbs'),
      phMinOpt: n('phMinOpt'),
      phMaxOpt: n('phMaxOpt'),
      phMaxAbs: n('phMaxAbs'),
      cicloMin: n('cicloMin'),
      cicloMax: n('cicloMax'),
      altitudMax: n('altitudMax'),
      texturaOpt: t('texturaOpt'),
      texturaTol: t('texturaTol'),
      drenajeOpt: t('drenajeOpt'),
      drenajeTol: t('drenajeTol'),
      fertilidadOpt: t('fertilidadOpt'),
      fertilidadTol: t('fertilidadTol'),
      salinidadOpt: t('salinidadOpt'),
      salinidadTol: t('salinidadTol'),
      profundidadOpt: t('profundidadOpt'),
      profundidadTol: t('profundidadTol'),
    );
  }

  // Días promedio del ciclo (para la línea de tiempo de Proyección)
  int? get cicloPromedio {
    if (cicloMin == null) return null;
    return ((cicloMin! + (cicloMax ?? cicloMin!)) / 2).round();
  }

  // Profundidad mínima de suelo (en metros) según el texto del archivo
  double? get profundidadMinimaM {
    final texto = (profundidadOpt ?? '').toLowerCase();
    if (texto.contains('profunda')) return 1.5;
    if (texto.contains('media')) return 0.5;
    if (texto.contains('somera')) return 0.2;
    return null;
  }

  // Texto corto para la tarjeta
  String get resumen {
    final partes = <String>[];
    if (tempMinOpt != null && tempMaxOpt != null) {
      partes.add('${formatoNumero(tempMinOpt!)}–${formatoNumero(tempMaxOpt!)} °C');
    }
    if (phMinOpt != null && phMaxOpt != null) {
      partes.add('pH ${formatoNumero(phMinOpt!)}–${formatoNumero(phMaxOpt!)}');
    }
    if (cicloMin != null) {
      partes.add('${cicloMin!.round()}–${(cicloMax ?? cicloMin!).round()} días');
    }
    return partes.isEmpty ? 'Ver ficha' : partes.join(' · ');
  }
}

class CultivosService {
  static Future<Map<String, FichaCultivo>> obtener() async {
    final http.Response respuesta;
    try {
      respuesta = await http.get(Uri.parse('$kServidorClima/api/cultivos')).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw Exception('el servidor no responde. ¿Está corriendo servidor_clima.py?');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(respuesta.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('respuesta inválida del servidor (${respuesta.statusCode})');
    }

    if (respuesta.statusCode != 200) {
      throw Exception(json['error'] ?? 'error ${respuesta.statusCode}');
    }

    final datos = json['cultivos'] as Map<String, dynamic>;
    return datos.map((nombre, valor) => MapEntry(nombre, FichaCultivo.fromJson(valor as Map<String, dynamic>)));
  }
}

// Ventana con la ficha completa del cultivo (todos los campos del archivo)
// ============================================================
// GUÍA DE EXPLORACIÓN
// ============================================================
class PasoGuia {
  final IconData icono;
  final String titulo;
  final String resumen;
  final List<String> puntos;
  final String consejo;
  final int? seccion; // índice del menú al que lleva (null = no lleva a ninguna)

  const PasoGuia(this.icono, this.titulo, this.resumen, this.puntos, this.consejo, [this.seccion]);
}

const List<PasoGuia> pasosGuia = [
  PasoGuia(
    Icons.rocket_launch_outlined,
    'Bienvenido a FARM-EK',
    'FARM-EK une datos de satélite, clima real y simulación para ayudarte a decidir qué sembrar en tu parcela.',
    [
      'Cada proyecto guarda la ubicación, medidas y suelo de una parcela.',
      'Recorre las secciones en orden: Terreno → Clima → Cultivar → Proyección.',
      'Puedes volver a abrir esta guía cuando quieras desde el menú lateral.',
    ],
    'Si ves datos de ejemplo, revisa que el servidor de clima y la API de suelo estén encendidos.',
  ),
  PasoGuia(
    Icons.layers_outlined,
    '1. Terreno',
    'Conoce lo que hay bajo la superficie de tu parcela.',
    [
      'El modelo 3D cambia con la textura, la humedad y la materia orgánica reales del suelo.',
      'Cambia a vista 2D para ver la planta y el corte del perfil con sus capas.',
      'Las tarjetas muestran pH, humedad, materia orgánica, textura, elevación y pendiente.',
      'Usa "Configurar terreno" para corregir medidas o valores del proyecto.',
    ],
    'Arenoso drena rápido; arcilloso retiene agua y se agrieta al secarse; franco es el más equilibrado.',
    0,
  ),
  PasoGuia(
    Icons.wb_sunny_outlined,
    '2. Clima',
    'Clima real de tu ubicación, actualizado cada 5 minutos.',
    [
      'Revisa el estado del cielo, temperatura, humedad, radiación y evaporación del día.',
      'La escena cambia a modo noche cuando oscurece en tu zona.',
      'Usa el botón de actualizar si quieres los datos al instante.',
    ],
    'Una evaporación alta con poca lluvia significa que tus cultivos necesitarán riego.',
    1,
  ),
  PasoGuia(
    Icons.grass_outlined,
    '3. Cultivar',
    'Explora 15 cultivos y lo que necesita cada uno.',
    [
      'Desliza las tarjetas para recorrer los cultivos.',
      'Toca "ⓘ" para abrir la ficha con temperatura, lluvia, pH, ciclo y tipo de suelo ideales.',
      'Compara esos rangos con los datos de tu Terreno y Clima.',
    ],
    'Si el pH de tu suelo está fuera del rango de un cultivo, ese cultivo rendirá menos.',
    2,
  ),
  PasoGuia(
    Icons.show_chart_outlined,
    '4. Proyección',
    'Simula el futuro de tu parcela con el método Monte Carlo.',
    [
      'Vista "Cultivo": curva de crecimiento y etapas de un cultivo.',
      'Vista "Rotación": se simulan 1,000 años posibles con el clima de tu ubicación.',
      'Elige "Sin riego / Con riego" y rotaciones de 3 o 4 cultivos.',
      'El porcentaje indica en cuántos futuros simulados salieron bien todos los cultivos.',
    ],
    'Pulsa "Volver a simular" después de cambiar el suelo o la ubicación del proyecto.',
    3,
  ),
  PasoGuia(
    Icons.flag_outlined,
    '¡Listo para explorar!',
    'Ya conoces todo el recorrido.',
    [
      'Empieza por Terreno para confirmar que los datos del suelo son correctos.',
      'Termina en Proyección para obtener tu mejor rotación.',
      'Crea varios proyectos para comparar parcelas distintas.',
    ],
    'Los resultados son una guía basada en datos; combínalos con la experiencia local.',
    0,
  ),
];

class GuiaExploracionDialog extends StatefulWidget {
  final int seccionInicial;
  const GuiaExploracionDialog({super.key, this.seccionInicial = 0});

  @override
  State<GuiaExploracionDialog> createState() => _GuiaExploracionDialogState();
}

class _GuiaExploracionDialogState extends State<GuiaExploracionDialog> {
  int _paso = 0;

  @override
  Widget build(BuildContext context) {
    final paso = pasosGuia[_paso];
    final ultimo = _paso == pasosGuia.length - 1;
    final ancho = math.min(MediaQuery.sizeOf(context).width - 32, 520.0);
    final alto = MediaQuery.sizeOf(context).height * 0.85;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho, maxHeight: alto),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Encabezado con degradado de marca
            Container(
              decoration: const BoxDecoration(gradient: Marca.degradado),
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('GUÍA DE EXPLORACIÓN',
                          style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const Spacer(),
                      Text('${_paso + 1} / ${pasosGuia.length}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                        child: Icon(paso.icono, color: Marca.neonYellow, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(paso.titulo,
                            style: Marca.titulo(size: 20, color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Contenido
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paso.resumen, style: const TextStyle(fontSize: 14, color: Marca.deepBlue, height: 1.4)),
                    const SizedBox(height: 14),
                    for (final punto in paso.puntos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: Icon(Icons.check_circle, size: 15, color: Marca.blueYonder),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(punto, style: const TextStyle(fontSize: 13, height: 1.35))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Marca.azulSuave,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Marca.borde),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lightbulb_outline, size: 18, color: Marca.electricBlue),
                          const SizedBox(width: 8),
                          Expanded(child: Text(paso.consejo, style: const TextStyle(fontSize: 12.5, color: Marca.deepBlue, height: 1.35))),
                        ],
                      ),
                    ),
                    if (paso.seccion != null && !ultimo) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(paso.seccion),
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Ir a esta sección'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Puntos de progreso
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pasosGuia.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _paso = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _paso ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _paso ? Marca.neonBlue : Marca.borde,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Botones
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  if (_paso > 0)
                    TextButton(onPressed: () => setState(() => _paso--), child: const Text('Anterior'))
                  else
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Saltar')),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Marca.neonBlue),
                    onPressed: () {
                      if (ultimo) {
                        Navigator.of(context).pop(paso.seccion);
                      } else {
                        setState(() => _paso++);
                      }
                    },
                    child: Text(ultimo ? 'Empezar' : 'Siguiente'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FichaCultivoDialog extends StatelessWidget {
  final String nombre;
  final FichaCultivo ficha;

  const FichaCultivoDialog({super.key, required this.nombre, required this.ficha});

  // Números con separador de miles y sin decimales innecesarios
  static String _num(double v) => v.abs() >= 1000 ? conMiles(v) : formatoNumero(v);

  String _rango(double? a, double? b, String unidad) {
    if (a == null && b == null) return '—';
    final ta = a == null ? '—' : _num(a);
    final tb = b == null ? '—' : _num(b);
    return '$ta – $tb $unidad'.trim();
  }

  Widget _seccion(String titulo, List<Widget> filas) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          ...filas,
        ],
      ),
    );
  }

  Widget _fila(String etiqueta, String? valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              (valor == null || valor.isEmpty) ? '—' : valor,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = ficha;
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Marca.deepBlue)),
          if (f.cientifico != null)
            Text(f.cientifico!, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _seccion('GENERAL', [
                _fila('Grupo de cultivo', f.grupo),
                _fila('Forma de vida', f.formaVida),
                _fila('Ciclo de vida', f.cicloVida),
                _fila('Nombres comunes', f.nombresComunes),
              ]),
              _seccion('TEMPERATURA', [
                _fila('Óptima', _rango(f.tempMinOpt, f.tempMaxOpt, '°C')),
                _fila('Absoluta (tolera)', _rango(f.tempMinAbs, f.tempMaxAbs, '°C')),
                _fila('Letal / helada', f.tempLetal == null ? null : '${formatoNumero(f.tempLetal!)} °C'),
              ]),
              _seccion('LLUVIA', [
                _fila('Óptima', _rango(f.lluviaMinOpt, f.lluviaMaxOpt, 'mm/año')),
                _fila('Absoluta (tolera)', _rango(f.lluviaMinAbs, f.lluviaMaxAbs, 'mm/año')),
              ]),
              _seccion('pH DEL SUELO', [
                _fila('Óptimo', _rango(f.phMinOpt, f.phMaxOpt, '')),
                _fila('Absoluto (tolera)', _rango(f.phMinAbs, f.phMaxAbs, '')),
              ]),
              _seccion('CICLO Y ALTITUD', [
                _fila('Ciclo de cultivo', _rango(f.cicloMin, f.cicloMax, 'días')),
                _fila('Altitud máxima', f.altitudMax == null ? null : '${_num(f.altitudMax!)} m'),
              ]),
              _seccion('SUELO', [
                _fila('Textura óptima', f.texturaOpt),
                _fila('Textura tolerada', f.texturaTol),
                _fila('Drenaje óptimo', f.drenajeOpt),
                _fila('Drenaje tolerado', f.drenajeTol),
                _fila('Fertilidad óptima', f.fertilidadOpt),
                _fila('Fertilidad tolerada', f.fertilidadTol),
                _fila('Salinidad óptima', f.salinidadOpt),
                _fila('Salinidad tolerada', f.salinidadTol),
                _fila('Profundidad óptima', f.profundidadOpt),
                _fila('Profundidad tolerada', f.profundidadTol),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar', style: TextStyle(color: Marca.neonBlue)),
        ),
      ],
    );
  }
}

// ============================================================
// 11. API DE SUELO (FastAPI + Google Earth Engine, publicada con ngrok)
// ============================================================

// Dirección de la API de suelo. Si cambia la URL de ngrok, cámbiala aquí.
const String kApiSuelo = 'http://localhost:8000'; // API de suelo en esta misma computadora (py main.py en la carpeta Api)

class DatosSuelo {
  final double? ph;
  final String? estadoPh;
  final double? humedad; // % de agua en el suelo (capacidad de campo)
  final double? arcilla, arena, limo; // %
  final double? materiaOrganica; // %
  final String? estadoMateriaOrganica;
  final double? elevacion; // m
  final double? pendiente; // grados

  const DatosSuelo({
    this.ph,
    this.estadoPh,
    this.humedad,
    this.arcilla,
    this.arena,
    this.limo,
    this.materiaOrganica,
    this.estadoMateriaOrganica,
    this.elevacion,
    this.pendiente,
  });

  factory DatosSuelo.fromJson(Map<String, dynamic> j) {
    double? n(String k) => (j[k] as num?)?.toDouble();
    return DatosSuelo(
      ph: n('ph'),
      estadoPh: j['estado_ph'] as String?,
      humedad: n('humedad'),
      arcilla: n('arcilla'),
      arena: n('arena'),
      limo: n('limo'),
      materiaOrganica: n('materia_organica'),
      estadoMateriaOrganica: j['estado_materia_organica'] as String?,
      elevacion: n('elevacion'),
      pendiente: n('pendiente'),
    );
  }

  // Clase de textura según el triángulo de texturas del USDA
  String get textura {
    final c = arcilla, a = arena, l = limo;
    if (c == null || a == null || l == null) return '—';
    if (l + 1.5 * c < 15) return 'Arenoso';
    if (l + 2 * c < 30) return 'Arenoso franco';
    if ((c >= 7 && c < 20 && a > 52) || (c < 7 && l < 50)) return 'Franco arenoso';
    if (c >= 7 && c < 27 && l >= 28 && l < 50 && a <= 52) return 'Franco';
    if ((l >= 50 && c >= 12 && c < 27) || (l >= 50 && l < 80 && c < 12)) return 'Franco limoso';
    if (l >= 80 && c < 12) return 'Limoso';
    if (c >= 20 && c < 35 && l < 28 && a > 45) return 'Franco arcillo arenoso';
    if (c >= 27 && c < 40 && a > 20 && a <= 45) return 'Franco arcilloso';
    if (c >= 27 && c < 40 && a <= 20) return 'Franco arcillo limoso';
    if (c >= 35 && a > 45) return 'Arcillo arenoso';
    if (c >= 40 && l >= 40) return 'Arcillo limoso';
    if (c >= 40) return 'Arcilloso';
    return 'Franco';
  }
}

class SueloService {
  static Future<DatosSuelo> obtener(double latitud, double longitud) async {
    final uri = Uri.parse('$kApiSuelo/suelo').replace(queryParameters: {
      'lat': latitud.toString(),
      'lon': longitud.toString(),
    });

    final http.Response respuesta;
    try {
      respuesta = await http.get(
        uri,
        // Sin este encabezado, ngrok responde con su página de aviso en lugar de los datos
        headers: {'ngrok-skip-browser-warning': 'true'},
      ).timeout(const Duration(seconds: 60)); // Earth Engine puede tardar varios segundos
    } catch (_) {
      throw Exception('la API de suelo no responde (¿está encendida y con ngrok activo?)');
    }

    if (respuesta.statusCode != 200) {
      throw Exception('la API de suelo respondió con error ${respuesta.statusCode}');
    }

    try {
      return DatosSuelo.fromJson(jsonDecode(respuesta.body) as Map<String, dynamic>);
    } catch (_) {
      throw Exception('respuesta inválida de la API de suelo');
    }
  }
}

// ============================================================
// 12. ROTACIÓN DE CULTIVOS (Monte Carlo en el servidor: /api/rotacion)
// ============================================================

class FilaRotacion {
  final List<String> rotacion;
  final double exito; // 0 a 1
  final double puntaje;
  final List<double> exitoPorCultivo;
  final double meses;
  final double? riegoMm; // mm = litros por m²

  const FilaRotacion({
    required this.rotacion,
    required this.exito,
    required this.puntaje,
    required this.exitoPorCultivo,
    required this.meses,
    this.riegoMm,
  });

  factory FilaRotacion.fromJson(Map<String, dynamic> j) => FilaRotacion(
        rotacion: (j['rotacion'] as List<dynamic>).cast<String>(),
        exito: (j['exito'] as num).toDouble(),
        puntaje: (j['puntaje'] as num).toDouble(),
        exitoPorCultivo: (j['exitoPorCultivo'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        meses: (j['mesesPromedio'] as num?)?.toDouble() ?? 0,
        riegoMm: (j['riegoNecesarioMm'] as num?)?.toDouble(),
      );
}

class ResultadoRotacion {
  final String mensaje;
  final FilaRotacion? mejor;
  final List<FilaRotacion> ranking;
  final int simulaciones;
  final int rotacionesEvaluadas;
  final String fuenteClima;
  final String? archivoClima;
  final String? avisoClima; // Si no se pudo usar el clima real de la ubicación

  const ResultadoRotacion({
    required this.mensaje,
    required this.mejor,
    required this.ranking,
    required this.simulaciones,
    required this.rotacionesEvaluadas,
    required this.fuenteClima,
    this.archivoClima,
    this.avisoClima,
  });

  factory ResultadoRotacion.fromJson(Map<String, dynamic> j) {
    final ranking = ((j['ranking'] as List<dynamic>?) ?? [])
        .map((e) => FilaRotacion.fromJson(e as Map<String, dynamic>))
        .toList();
    return ResultadoRotacion(
      mensaje: j['mensaje'] as String? ?? '',
      mejor: ranking.isEmpty ? null : ranking.first,
      ranking: ranking,
      simulaciones: (j['simulaciones'] as num?)?.toInt() ?? 0,
      rotacionesEvaluadas: (j['rotacionesEvaluadas'] as num?)?.toInt() ?? 0,
      fuenteClima: j['fuenteClima'] as String? ?? 'desconocido',
      archivoClima: j['archivoClima'] as String?,
      avisoClima: j['avisoClima'] as String?,
    );
  }
}

class RotacionService {
  static Future<ResultadoRotacion> obtener({
    required double latitud,
    required double longitud,
    required double ph,
    required double profundidad,
    required bool riego,
    int largo = 4,
    double? humedad,
    double? materiaOrganica,
    double? arcilla,
    double? arena,
    double? elevacion,
    double? pendiente,
  }) async {
    final uri = Uri.parse('$kServidorClima/api/rotacion').replace(queryParameters: {
      'lat': latitud.toString(),
      'lon': longitud.toString(),
      'ph': ph.toString(),
      'profundidad': profundidad.toString(),
      'riego': riego ? '1' : '0',
      'largo': largo.toString(),
      if (humedad != null) 'humedad': humedad.toString(),
      if (materiaOrganica != null) 'mo': materiaOrganica.toString(),
      if (arcilla != null) 'arcilla': arcilla.toString(),
      if (arena != null) 'arena': arena.toString(),
      if (elevacion != null) 'elevacion': elevacion.toString(),
      if (pendiente != null) 'pendiente': pendiente.toString(),
    });

    final http.Response respuesta;
    try {
      // La primera vez en una ubicación nueva se descargan 12 meses de clima: se da más tiempo
      respuesta = await http.get(uri).timeout(const Duration(minutes: 4));
    } catch (_) {
      throw Exception('el servidor no responde. ¿Está corriendo servidor_clima.py?');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(respuesta.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('respuesta inválida del servidor (${respuesta.statusCode})');
    }
    if (respuesta.statusCode != 200) {
      throw Exception(json['error'] ?? 'error ${respuesta.statusCode}');
    }
    return ResultadoRotacion.fromJson(json);
  }
}
