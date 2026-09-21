/// 立创分类（英文）→ 本地分类（中文）映射。
///
/// 未命中时返回 null，调用方按 PRD F4 归入大类"未分类"，用户可手动调整。
class LcscCategoryMapper {
  const LcscCategoryMapper._();

  /// 子类（立创 catalogName）→ 本地子类名。
  static const Map<String, String> _subMap = {
    'ceramic capacitors': '贴片电容(MLCC)',
    'mlcc': '贴片电容(MLCC)',
    'aluminum electrolytic capacitors': '铝电解电容',
    'aluminum electrolytic capacitor': '铝电解电容',
    'tantalum capacitors': '钽电容',
    'tantalum capacitor': '钽电容',
    'film capacitors': '薄膜电容',
    'supercapacitors': '超级电容',
    'variable capacitors': '可调电容',
    'trimmer capacitors': '可调电容',
    'chip resistor': '贴片电阻',
    'chip resistor - array': '排阻',
    'through hole resistors': '插件电阻',
    'resistor networks': '排阻',
    'potentiometers': '电位器',
    'trimmer potentiometers': '电位器',
    'ntc thermistors': '热敏电阻',
    'ptc thermistors': '热敏电阻',
    'varistors': '压敏电阻',
    'inductors': '贴片电感',
    'power inductors': '贴片电感',
    'fixed inductors': '插件电感',
    'ferrite beads': '磁珠',
    'common mode chokes': '共模电感',
    'transformers': '变压器',
    'rectifier diodes': '整流二极管',
    'schottky diodes': '肖特基二极管',
    'zener diodes': '稳压/TVS 二极管',
    'tvs diodes': '稳压/TVS 二极管',
    'switching diodes': '开关二极管',
    'fast recovery diodes': '快恢复二极管',
    'bipolar transistors': '三极管(BJT)',
    'mosfets': '场效应管(MOSFET)',
    'igbts': 'IGBT',
    'microcontrollers': 'MCU',
    'mcu': 'MCU',
    'microprocessors': 'MPU/处理器',
    'logic gates': '逻辑门',
    'flip flops': '触发器/锁存器',
    'level shifters': '电平转换',
    'shift registers': '移位寄存器',
    'operational amplifiers': '运算放大器',
    'comparators': '比较器',
    'audio amplifiers': '音频放大器',
    'instrumentation amplifiers': '仪表放大器',
    'ldo': 'LDO',
    'linear voltage regulators': 'LDO',
    'dc-dc': 'DC-DC',
    'battery management': '充电管理',
    'voltage references': '电压基准',
    'supervisors': '电源监控',
    'gate drivers': '栅极驱动',
    'uart': 'UART/RS232',
    'rs-485': 'RS485',
    'can transceivers': 'CAN',
    'usb interface ics': 'USB',
    'ethernet ics': '以太网',
    'eeprom': 'EEPROM',
    'flash memory': 'Flash',
    'sram': 'SRAM',
    'dram': 'DRAM',
    'memory cards': 'SD/TF 卡',
    'adc': 'ADC',
    'dac': 'DAC',
    'wifi modules': '无线模块(WiFi/BT)',
    'bluetooth modules': '无线模块(WiFi/BT)',
    'rf ics': '射频芯片',
    'antennas': '天线',
    'crystals': '晶振',
    'oscillators': '振荡器',
    'rtc': '实时时钟(RTC)',
    'temperature sensors': '温度传感器',
    'humidity sensors': '湿度传感器',
    'accelerometers': '加速度/陀螺仪',
    'gyroscopes': '加速度/陀螺仪',
    'ambient light sensors': '光传感器',
    'current sensors': '电流/电压传感器',
    'distance sensors': '距离传感器',
    'leds': 'LED',
    'led displays': '数码管',
    'digital displays': '数码管',
    'lcd displays': 'LCD',
    'oled displays': 'OLED',
    'optocouplers': '光耦',
    'photodiodes': '红外器件',
    'infrared emitters': '红外器件',
    'pins headers': '排针排母',
    'pin headers': '排针排母',
    'female headers': '排针排母',
    'box headers': '简牛/牛角',
    'terminal blocks': '接线端子',
    'usb connectors': 'USB 连接器',
    'ffc/fpc connectors': 'FPC/排线座',
    'tactile switches': '轻触开关',
    'slide switches': '拨动开关',
    'toggle switches': '自锁开关',
    'rotary encoders': '编码器',
    'fuses': '保险丝',
    'ptc resettable fuses': '自恢复保险丝(PTC)',
    'esd protection': 'ESD 保护',
    'relays': '继电器',
    'buzzers': '蜂鸣器',
    'motors': '马达/电机',
    'fans': '散热风扇',
  };

  /// 大类（立创 parentCatalogName）→ 本地大类名。
  static const Map<String, String> _topMap = {
    'capacitors': '电容',
    'resistors': '电阻',
    'inductors': '电感磁珠变压器',
    'transformers': '电感磁珠变压器',
    'diodes': '二极管',
    'transistors': '晶体管',
    'discrete semiconductors': '晶体管',
    'integrated circuits': '微控制器与处理器',
    'embedded processors': '微控制器与处理器',
    'microcontrollers': '微控制器与处理器',
    'logic ics': '逻辑器件',
    'amplifiers': '放大器与比较器',
    'power management': '电源管理',
    'power management ics': '电源管理',
    'interfaces': '接口芯片',
    'interface ics': '接口芯片',
    'memory': '存储器',
    'data converters': '数据转换',
    'rf & wireless': '射频与无线',
    'wireless': '射频与无线',
    'clock & timing': '时钟与计时',
    'crystals & oscillators': '时钟与计时',
    'sensors': '传感器',
    'optoelectronics': '光电器件与显示',
    'displays': '光电器件与显示',
    'led lighting': '光电器件与显示',
    'connectors': '连接器与端子',
    'switches': '开关与按键',
    'circuit protection': '电路保护',
    'relays': '继电器/蜂鸣器/马达',
    'motors & actuators': '继电器/蜂鸣器/马达',
    'modules': '功能模块与开发板',
    'development boards': '功能模块与开发板',
    'batteries': '电池与电源配件',
    'battery accessories': '电池与电源配件',
    'tools': '工具与耗材',
    'consumables': '工具与耗材',
    'passives': '电容',
  };

  static String? subCategoryOf(String? catalogName) {
    final key = _normalize(catalogName);
    if (key == null) return null;
    final direct = _subMap[key];
    if (direct != null) return direct;
    for (final entry in _subMap.entries) {
      if (key.contains(entry.key) || entry.key.contains(key)) {
        return entry.value;
      }
    }
    return null;
  }

  static String? topCategoryOf(String? parentName, String? catalogName) {
    final key = _normalize(parentName);
    if (key != null) {
      final direct = _topMap[key];
      if (direct != null) return direct;
      for (final entry in _topMap.entries) {
        if (key.contains(entry.key) || entry.key.contains(key)) {
          return entry.value;
        }
      }
    }
    // 大类未命中时，尝试用子类名反推大类。
    final sub = subCategoryOf(catalogName);
    if (sub != null) {
      for (final entry in _subKeywordToTop.entries) {
        if (sub.contains(entry.key)) return entry.value;
      }
    }
    return null;
  }

  static const Map<String, String> _subKeywordToTop = {
    '电容': '电容',
    '电阻': '电阻',
    '电感': '电感磁珠变压器',
    '磁珠': '电感磁珠变压器',
    '变压器': '电感磁珠变压器',
    '二极管': '二极管',
    '三极管': '晶体管',
    '场效应管': '晶体管',
    'IGBT': '晶体管',
    'MCU': '微控制器与处理器',
    'MPU': '微控制器与处理器',
    '逻辑': '逻辑器件',
    '触发器': '逻辑器件',
    '电平转换': '逻辑器件',
    '移位寄存器': '逻辑器件',
    '放大': '放大器与比较器',
    '比较器': '放大器与比较器',
    'LDO': '电源管理',
    'DC-DC': '电源管理',
    '充电管理': '电源管理',
    '电压基准': '电源管理',
    '电源监控': '电源管理',
    '栅极驱动': '电源管理',
    'UART': '接口芯片',
    'RS485': '接口芯片',
    'CAN': '接口芯片',
    'USB': '接口芯片',
    '以太网': '接口芯片',
    'EEPROM': '存储器',
    'Flash': '存储器',
    'SRAM': '存储器',
    'DRAM': '存储器',
    'ADC': '数据转换',
    'DAC': '数据转换',
    '无线': '射频与无线',
    '射频': '射频与无线',
    '天线': '射频与无线',
    '晶振': '时钟与计时',
    '振荡器': '时钟与计时',
    'RTC': '时钟与计时',
    '传感器': '传感器',
    'LED': '光电器件与显示',
    '数码管': '光电器件与显示',
    'LCD': '光电器件与显示',
    'OLED': '光电器件与显示',
    '光耦': '光电器件与显示',
    '红外': '光电器件与显示',
    '排针': '连接器与端子',
    '牛角': '连接器与端子',
    '接线端子': '连接器与端子',
    'FPC': '连接器与端子',
    '开关': '开关与按键',
    '编码器': '开关与按键',
    '保险丝': '电路保护',
    'ESD': '电路保护',
    '继电器': '继电器/蜂鸣器/马达',
    '蜂鸣器': '继电器/蜂鸣器/马达',
    '电机': '继电器/蜂鸣器/马达',
    '风扇': '继电器/蜂鸣器/马达',
    '模块': '功能模块与开发板',
    '开发板': '功能模块与开发板',
    '电池': '电池与电源配件',
    '工具': '工具与耗材',
  };

  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }
}
