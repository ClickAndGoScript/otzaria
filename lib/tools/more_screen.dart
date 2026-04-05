import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/dictionary/dictionary_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_widget.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/view/plugin_side_panel.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';

abstract class ToolDescriptor {
  final String toolId;
  final String label;
  final int order;
  const ToolDescriptor(
      {required this.toolId, required this.label, required this.order});
  Widget buildTab(BuildContext context);
  Widget buildPage(BuildContext context);
}

class BuiltInToolDescriptor extends ToolDescriptor {
  final IconData? icon;
  final String? imageIcon;
  final Widget Function() pageBuilder;

  const BuiltInToolDescriptor({
    required super.toolId,
    required super.label,
    required super.order,
    this.icon,
    this.imageIcon,
    required this.pageBuilder,
  });

  @override
  Widget buildTab(BuildContext context) {
    if (imageIcon != null) {
      return SizedBox(
        width: 100,
        child:
            Tab(text: label, icon: ImageIcon(AssetImage(imageIcon!), size: 20)),
      );
    }
    return SizedBox(
      width: 100,
      child: Tab(text: label, icon: Icon(icon, size: 20)),
    );
  }

  @override
  Widget buildPage(BuildContext context) => pageBuilder();
}

class PluginToolDescriptor extends ToolDescriptor {
  final InstalledPlugin plugin;
  PluginToolDescriptor({required this.plugin})
      : super(
            toolId: plugin.pluginId,
            label: plugin.manifest.toolTabTitle,
            order: plugin.manifest.toolTabOrder);

  @override
  Widget buildTab(BuildContext context) {
    return SizedBox(
      width: 100,
      child: Tab(
        text: label,
        icon: null, // ללא אייקון — גם לתוספים זמניים
      ),
    );
  }

  @override
  Widget buildPage(BuildContext context) => PluginTabPage(
        key: ValueKey(plugin.pluginId),
        plugin: plugin,
      );
}

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  MoreScreenState createState() => MoreScreenState();
}

class MoreScreenState extends State<MoreScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const int _calendarFocusRetryCount = 6;
  TabController? _tabController;
  final GlobalKey<CalendarWidgetState> _calendarKey =
      GlobalKey<CalendarWidgetState>();
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();

  List<ToolDescriptor> _descriptors = [];
  List<Widget> _pages = [];
  List<Widget> _tabWidgets = [];
  String? _selectedToolId;
  bool _isPanelOpen = false;
  InstalledPlugin? _transientPlugin;
  // מונע rebuild מרובה של הטאבים כאשר הזהות המלאה של הלשוניות לא השתנתה
  String _lastDescriptorsSignature = '';

  String _descriptorSignature(List<ToolDescriptor> descriptors) {
    return descriptors.map((descriptor) => descriptor.toolId).join('|');
  }

  void _requestCalendarFocus(
      {int remainingAttempts = _calendarFocusRetryCount}) {
    if (!mounted) return;
    final calendarState = _calendarKey.currentState;
    if (calendarState != null) {
      calendarState.requestKeyboardFocus();
      return;
    }
    if (remainingAttempts <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _requestCalendarFocus(remainingAttempts: remainingAttempts - 1);
        }
      });
    });
  }

  void requestActiveTabFocus() {
    if (_tabController?.index != null &&
        _descriptors[_tabController!.index].toolId == 'builtin.calendar') {
      _requestCalendarFocus();
    }
  }

  void _handleTabChange() {
    if (_tabController == null) return;
    final currentToolId = _descriptors[_tabController!.index].toolId;
    if (currentToolId != _selectedToolId) {
      setState(() {
        _selectedToolId = currentToolId;
      });
      if (currentToolId == 'builtin.calendar') {
        _requestCalendarFocus();
      }
    }
  }

  List<ToolDescriptor> _buildBaseDescriptors() {
    return [
      BuiltInToolDescriptor(
        toolId: 'builtin.calendar',
        label: 'לוח שנה',
        icon: FluentIcons.calendar_24_regular,
        order: 10,
        pageBuilder: () => BlocBuilder<CalendarCubit, CalendarState>(
          builder: (context, _) => CalendarWidget(key: _calendarKey),
        ),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.shamor_zachor',
        label: 'שמור וזכור',
        imageIcon: 'assets/icon/שמור וזכור שחור ריק.png',
        order: 20,
        pageBuilder: () => ShamorZachorWidget(onTitleChanged: (_) {}),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.measurements',
        label: 'מדות ושיעורים',
        icon: FluentIcons.ruler_24_regular,
        order: 30,
        pageBuilder: () => const MeasurementConverterScreen(),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.notes',
        label: 'הערות אישיות',
        icon: FluentIcons.note_24_regular,
        order: 40,
        pageBuilder: () => const PersonalNotesManagerScreen(),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.gematria',
        label: 'גימטריה',
        icon: FluentIcons.calculator_24_regular,
        order: 50,
        pageBuilder: () => GematriaSearchScreen(key: _gematriaKey),
      ),
      BuiltInToolDescriptor(
        toolId: 'builtin.dictionary',
        label: 'מילון',
        icon: FluentIcons.book_24_regular,
        order: 60,
        pageBuilder: () => const DictionaryScreen(),
      ),
    ];
  }

  void _openPluginTransiently(InstalledPlugin plugin) {
    if (plugin.pinned) {
      final index = _descriptors.indexWhere((d) => d.toolId == plugin.pluginId);
      if (index != -1) {
        _tabController?.animateTo(index);
      }
      return;
    }
    // מגדיר את הפלאגין הזמני ומיד מבצע rebuild — ללא setState נפרד
    _transientPlugin = plugin;
    _selectedToolId = plugin.pluginId;
    final blocState = context.read<PluginSystemBloc>().state;
    if (blocState is PluginSystemLoaded) {
      _rebuildTabs(blocState.pinnedPlugins, transient: _transientPlugin);
    }
  }

  void _applyTabState(
    List<InstalledPlugin> pinnedPlugins, {
    InstalledPlugin? transient,
    required bool notify,
  }) {
    final newDescriptors = <ToolDescriptor>[
      ..._buildBaseDescriptors(),
      ...pinnedPlugins.map((p) => PluginToolDescriptor(plugin: p)),
    ];
    if (transient != null) {
      if (!pinnedPlugins.any((p) => p.pluginId == transient.pluginId)) {
        newDescriptors.add(PluginToolDescriptor(plugin: transient));
      }
    }

    newDescriptors.sort((a, b) => a.order.compareTo(b.order));
    final newSignature = _descriptorSignature(newDescriptors);
    if (newSignature == _lastDescriptorsSignature && _tabController != null) {
      return;
    }
    _lastDescriptorsSignature = newSignature;

    int newIndex = 0;
    if (_selectedToolId != null) {
      newIndex = newDescriptors.indexWhere((t) => t.toolId == _selectedToolId);
      if (newIndex == -1) newIndex = 0;
    }

    _selectedToolId = newDescriptors[newIndex].toolId;

    final newController = TabController(
        length: newDescriptors.length, initialIndex: newIndex, vsync: this);
    newController.addListener(_handleTabChange);

    final oldController = _tabController;
    _tabController = newController;

    void applyState() {
      _descriptors = newDescriptors;
      _tabWidgets = newDescriptors.map((t) => t.buildTab(context)).toList();
      _pages = newDescriptors.map((t) => t.buildPage(context)).toList();
    }

    if (notify) {
      setState(applyState);
    } else {
      applyState();
    }

    if (oldController != null) {
      oldController.removeListener(_handleTabChange);
      // דחיית ה-dispose למסגרת הבאה — מונע dispose אגרסיבי
      SchedulerBinding.instance
          .addPostFrameCallback((_) => oldController.dispose());
    }
  }

  void _rebuildTabs(List<InstalledPlugin> pinnedPlugins,
      {InstalledPlugin? transient}) {
    if (!mounted) return;
    _applyTabState(
      pinnedPlugins,
      transient: transient,
      notify: true,
    );
  }

  @override
  void initState() {
    super.initState();
    _applyTabState([], notify: false);
  }

  void resetToCalendar() {
    final calendarIndex =
        _descriptors.indexWhere((t) => t.toolId == 'builtin.calendar');
    if (calendarIndex != -1 && _tabController?.index != calendarIndex) {
      _tabController?.animateTo(calendarIndex);
      return;
    }
    _requestCalendarFocus();
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isMoreScreenActive =
        context.select((NavigationBloc bloc) => bloc.state.currentScreen) ==
            Screen.more;

    if (isMoreScreenActive && _selectedToolId == 'builtin.calendar') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) requestActiveTabFocus();
      });
    }

    return BlocListener<PluginSystemBloc, PluginSystemState>(
      listener: (context, state) {
        if (state is PluginSystemLoaded) {
          _rebuildTabs(state.pinnedPlugins, transient: _transientPlugin);
        } else if (state is PluginSystemOverwriteRequired) {
          showWarningDialog(
            context: context,
            title: 'התוסף כבר קיים',
            content:
                'התוסף "${state.pluginName}" בגרסה ${state.version} כבר מותקן.',
            subtitle: 'האם ברצונך להתקין מחדש ולדרוס אותו?',
            cancelText: 'ביטול',
            confirmText: 'התקן מחדש',
          ).then((value) {
            if (!context.mounted) return;
            if (value == true) {
              context.read<PluginSystemBloc>().add(
                    InstallPluginRequested(state.archivePath,
                        forceOverwrite: true),
                  );
            } else {
              context.read<PluginSystemBloc>().add(LoadPlugins());
            }
          });
        } else if (state is PluginSystemInstallRequiresPermissions) {
          final permList = state.manifest.permissions.isEmpty
              ? 'אין הרשאות מיוחדות נדרשות'
              : state.manifest.permissions.join('\n');
          showWarningDialog(
            context: context,
            title: 'אישור התקנת תוסף',
            content:
                'התוסף "${state.manifest.name}" מבקש גישה למשאבי מערכת.\n\nהרשאות נדרשות:\n$permList',
            subtitle: 'האם ברצונך לאשר הרשאות אלו ולהתקין את התוסף?',
            cancelText: 'ביטול',
            confirmText: 'התקן וקבל',
          ).then((value) {
            if (!context.mounted) return;
            if (value == true) {
              context
                  .read<PluginSystemBloc>()
                  .add(ConfirmPluginInstall(state.tempDirPath, state.manifest));
            } else {
              context
                  .read<PluginSystemBloc>()
                  .add(CancelPluginInstall(state.tempDirPath));
            }
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: _tabController == null
              ? null
              : TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  tabs: _tabWidgets,
                ),
          actions: [
            IconButton(
              icon: const Icon(FluentIcons.puzzle_piece_24_regular),
              onPressed: () {
                setState(() {
                  _isPanelOpen = !_isPanelOpen;
                });
              },
              tooltip: 'תוספים',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: Theme.of(context).dividerColor,
              height: 1.0,
            ),
          ),
        ),
        body: _tabController == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  TabBarView(
                    key: ValueKey(_descriptorSignature(_descriptors)),
                    controller: _tabController,
                    children: _pages,
                  ),
                  if (_isPanelOpen)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: PluginSidePanel(
                        onPluginSelected: (plugin) {
                          _openPluginTransiently(plugin);
                          // הפאנל נשאר פתוח — המשתמש יכול להמשיך לגלוש
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
