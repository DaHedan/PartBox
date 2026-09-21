/// 内置立创分类（附录 B）与仓库种子数据。
class SeedCategory {
  const SeedCategory(this.name, this.icon, [this.subs = const []]);

  final String name;
  final String icon;
  final List<String> subs;
}

/// 大类 id=1 固定为"未分类"，不可删除。
const String kUncategorizedName = '未分类';
const int kUncategorizedCategoryId = 1;

const List<SeedCategory> kSeedCategories = [
  SeedCategory('电容', 'capacitor', [
    '贴片电容(MLCC)',
    '铝电解电容',
    '钽电容',
    '薄膜电容',
    '超级电容',
    '可调电容',
  ]),
  SeedCategory('电阻', 'resistor', [
    '贴片电阻',
    '插件电阻',
    '排阻',
    '电位器',
    '热敏电阻',
    '压敏电阻',
  ]),
  SeedCategory('电感磁珠变压器', 'inductor', [
    '贴片电感',
    '插件电感',
    '磁珠',
    '共模电感',
    '变压器',
  ]),
  SeedCategory('二极管', 'diode', [
    '整流二极管',
    '肖特基二极管',
    '稳压/TVS 二极管',
    '开关二极管',
    '快恢复二极管',
  ]),
  SeedCategory('晶体管', 'transistor', [
    '三极管(BJT)',
    '场效应管(MOSFET)',
    'IGBT',
  ]),
  SeedCategory('微控制器与处理器', 'mcu', ['MCU', 'MPU/处理器']),
  SeedCategory('逻辑器件', 'logic', [
    '逻辑门',
    '触发器/锁存器',
    '电平转换',
    '译码器/复用器',
    '移位寄存器',
  ]),
  SeedCategory('放大器与比较器', 'amplifier', [
    '运算放大器',
    '比较器',
    '音频放大器',
    '仪表放大器',
  ]),
  SeedCategory('电源管理', 'power', [
    'LDO',
    'DC-DC',
    '充电管理',
    '电压基准',
    '电源监控',
    '栅极驱动',
  ]),
  SeedCategory('接口芯片', 'interface', [
    'UART/RS232',
    'RS485',
    'CAN',
    'USB',
    '以太网',
    'I2C/SPI 扩展',
  ]),
  SeedCategory('存储器', 'storage', [
    'EEPROM',
    'Flash',
    'SRAM',
    'DRAM',
    'SD/TF 卡',
  ]),
  SeedCategory('数据转换', 'converter', ['ADC', 'DAC']),
  SeedCategory('射频与无线', 'wireless', [
    '无线模块(WiFi/BT)',
    '射频芯片',
    '天线',
    '射频连接器',
  ]),
  SeedCategory('时钟与计时', 'clock', [
    '晶振',
    '振荡器',
    '实时时钟(RTC)',
    '时钟芯片',
  ]),
  SeedCategory('传感器', 'sensor', [
    '温度传感器',
    '湿度传感器',
    '加速度/陀螺仪',
    '光传感器',
    '电流/电压传感器',
    '距离传感器',
  ]),
  SeedCategory('光电器件与显示', 'led', [
    'LED',
    '数码管',
    'LCD',
    'OLED',
    '光耦',
    '红外器件',
  ]),
  SeedCategory('连接器与端子', 'connector', [
    '排针排母',
    '简牛/牛角',
    '接线端子',
    'USB 连接器',
    'FPC/排线座',
  ]),
  SeedCategory('开关与按键', 'switch', [
    '轻触开关',
    '拨动开关',
    '自锁开关',
    '按键帽',
    '编码器',
  ]),
  SeedCategory('电路保护', 'protect', [
    '保险丝',
    '自恢复保险丝(PTC)',
    'TVS 管',
    'ESD 保护',
    '气体放电管',
  ]),
  SeedCategory('继电器/蜂鸣器/马达', 'relay', [
    '继电器',
    '蜂鸣器',
    '马达/电机',
    '散热风扇',
  ]),
  SeedCategory('功能模块与开发板', 'module', [
    '传感器模块',
    '电源模块',
    '通信模块',
    '开发板',
  ]),
  SeedCategory('电池与电源配件', 'battery', [
    '电池',
    '电池座',
    '电源适配器',
    '电源线/杜邦线',
  ]),
  SeedCategory('工具与耗材', 'tool', [
    '焊接工具',
    '镊子/钳子',
    '焊锡/助焊剂',
    '收纳盒/元件盒',
  ]),
];

/// 内置仓库：id=1 固定为"未分配"，不可删除。
const String kUnassignedLocationName = '未分配';
const int kUnassignedLocationId = 1;
