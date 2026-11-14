/*
 * DDT's USBKA: USB keyboard adapter for the CBM-II B128/B256 High-Profile.
 *
 * Firmware release: 20261113
 * 
 * https://github.com/0x444454/cbm2/edit/main/usbka
 *
 * Main hw components:
 *   Arduino Mega 2560 R3
 *   CH9350L USB keyboard host module on Serial1
 *   MT8816 8x16 analog crosspoint switch
 *
 * UART (115200 baud with the default CH9350L module setting):
 *   Mega D18 / TX1 -> CH9350L RX
 *   Mega D19 / RX1 <- CH9350L TX
 *
 * MT8816 control:
 *   D30 -> AX0
 *   D31 -> AX1
 *   D32 -> AX2
 *   D33 -> AX3
 *   D34 -> AY0
 *   D35 -> AY1
 *   D36 -> AY2
 *   D37 -> DATA
 *   D38 -> STROBE
 *   D39 -> RESET (PCB has pull-up to +5V)
 *   CS  -> +5 V
 *   VDD -> +5 V (PCB has bypass capacitor)
 *   VSS -> GND
 *   VEE -> GND
 *
 * MT8816 matrix layout:
 *   X0..X7   = PB0..PB7
 *   X8..X15  = PA0..PA7
 *   Y0..Y5   = PC0..PC5
 *   Y6,Y7    = unused
 *
 * B128 DB25:
 *   PB0..PB7 -> 5,6,7,8,9,10,11,12
 *   PA0..PA7 -> 1,14,2,15,3,16,4,17
 *   PC0..PC5 -> 18,19,20,21,25,13
 *   pin 22   -> GND
 *
 * USBKA opens and closes MT8816 crosspoints on USB key transitions.
 * The CBM-II scans those contacts as it would a passive keyboard matrix.
 */

#include <avr/io.h>

// CH9350L supported UART rates are 38400, 57600, 115200, and 300000.
// The normal/default module setting is 115200.
constexpr uint32_t CH9350_BAUD = 115200;

// Debug logging controls only.
int debug_log_raw = 0;     // 0..1: CH9350L status, key frames and valid report byte changes
int debug_log_hid = 0;     // 0..1: decoded HID transitions and unsupported report notices
int debug_log_us_iso = 2;  // 0=disabled, 1=press, 2=press and release
int debug_log_conv = 1;    // 0=disabled, 1=converted B128/B256 key presses, 2=also print CBM-II port bits and physical MT8816 X/Y lines

// The observed 0x0C report contains the modifier byte at hid[1], followed by a 15-byte bitmap at hid[2]..hid[16].
// The bitmap is usage-indexed from 0x00.
constexpr uint8_t HID_NKRO_USAGE_BASE = 0x00;

constexpr uint8_t MATRIX_SCAN_COUNT = 16;
constexpr uint8_t MATRIX_RETURN_COUNT = 6;

// ---------------------------------------------------------------------------
// MT8816
// ---------------------------------------------------------------------------
//
// D30..D37 are ATmega2560 PORTC bits PC7..PC0, respectively:
//
//   D30 / PC7 = AX0
//   D31 / PC6 = AX1
//   D32 / PC5 = AX2
//   D33 / PC4 = AX3
//   D34 / PC3 = AY0
//   D35 / PC2 = AY1
//   D36 / PC1 = AY2
//   D37 / PC0 = DATA
//
// D38 = PD7 = STROBE
// D39 = PG2 = RESET
//
// Since PORTC is dedicated to the MT8816, the complete X/Y address plus DATA
// bit can be loaded with one AVR port write.

constexpr uint8_t MT_STROBE_BIT = PD7;  // Arduino D38
constexpr uint8_t MT_RESET_BIT  = PG2;  // Arduino D39

static inline uint8_t mt8816_control_byte(uint8_t x, uint8_t y, bool closed) {
  uint8_t value = 0;

  // AX0..AX3 -> PC7..PC4
  if (x & 0x01) value |= _BV(PC7);
  if (x & 0x02) value |= _BV(PC6);
  if (x & 0x04) value |= _BV(PC5);
  if (x & 0x08) value |= _BV(PC4);

  // AY0..AY2 -> PC3..PC1
  if (y & 0x01) value |= _BV(PC3);
  if (y & 0x02) value |= _BV(PC2);
  if (y & 0x04) value |= _BV(PC1);

  // DATA -> PC0
  if (closed) value |= _BV(PC0);

  return value;
}

static inline uint8_t mt8816_x_address(uint8_t x) {
  // MT8816 X-address decode is not numerically ordered.
  // Address 0..15 selects:
  // X0,X1,X2,X3,X4,X5,X12,X13,X6,X7,X8,X9,X10,X11,X14,X15
  //
  // Convert the physical/logical X number to the required AX3..AX0 address.
  if (x <= 5)  return x;
  if (x <= 11) return x + 2;  // X6..X11  -> addresses 8..13
  if (x <= 13) return x - 6;  // X12..X13 -> addresses 6..7
  return x;                    // X14..X15  -> addresses 14..15
}

static inline void mt8816_set(uint8_t x, uint8_t y, bool closed) {
  if (x >= 16 || y >= 8) {
    return;
  }

  const uint8_t x_address = mt8816_x_address(x);

  // STROBE idle LOW.
  PORTD &= static_cast<uint8_t>(~_BV(MT_STROBE_BIT));

  // Address + DATA become valid together.
  PORTC = mt8816_control_byte(x_address, y, closed);

  // STROBE is active HIGH.  The data is latched on the falling edge.
  PORTD |= _BV(MT_STROBE_BIT);
  asm volatile("nop");
  PORTD &= static_cast<uint8_t>(~_BV(MT_STROBE_BIT));
}

void mt8816_reset() {
  // RESET is active HIGH and asynchronously opens all crosspoints.
  PORTG |= _BV(MT_RESET_BIT);
  delayMicroseconds(1);
  PORTG &= static_cast<uint8_t>(~_BV(MT_RESET_BIT));
}

void setup_mt8816() {
  // Preload safe states before enabling the outputs.
  PORTC = 0x00;  // address 0, DATA=0
  PORTD &= static_cast<uint8_t>(~_BV(MT_STROBE_BIT));
  PORTG |= _BV(MT_RESET_BIT);  // hold reset active while configuring pins

  // D30..D37 / PORTC: AX0..AX3, AY0..AY2, DATA.
  DDRC = 0xFF;

  // D38 / PD7: STROBE.
  DDRD |= _BV(MT_STROBE_BIT);

  // D39 / PG2: RESET.
  DDRG |= _BV(MT_RESET_BIT);

  delayMicroseconds(1);
  PORTG &= static_cast<uint8_t>(~_BV(MT_RESET_BIT));
}

// ---------------------------------------------------------------------------
// CH9350L parser state
// ---------------------------------------------------------------------------

constexpr uint8_t CH_MAX_DATA_LENGTH = 71;

enum CHParserState : uint8_t {
  WAIT_HEADER_57,
  WAIT_HEADER_AB,
  WAIT_COMMAND,
  READ_LENGTH,
  READ_DATA,
  READ_STATUS
};

CHParserState ch_parser_state = WAIT_HEADER_57;
uint8_t ch_command = 0;
uint8_t ch_data_length = 0;
uint8_t ch_data_index = 0;
uint8_t ch_data[CH_MAX_DATA_LENGTH];
uint8_t previous_raw[CH_MAX_DATA_LENGTH];
uint8_t previous_raw_length = 0;
bool previous_raw_valid = false;

// HID state. These are maintained regardless of debug settings.
bool hid_pressed[256] = {};
bool hid_state_valid = false;
bool consumer_pressed[256] = {};
bool consumer_state_valid = false;
bool caps_lock_state = false;
bool us_iso_shift_at_press[256] = {};
bool us_iso_caps_at_press[256] = {};

// ---------------------------------------------------------------------------
// Logical B128/B256 keys
// ---------------------------------------------------------------------------

constexpr uint16_t BKEY_HID_BASE = 0x0100;
constexpr uint16_t BKEY_SPECIAL_BASE = 0x0200;
constexpr uint16_t BKEY_NONE = 0x0000;

constexpr uint16_t BKEY_NUMPAD_QUESTION = BKEY_SPECIAL_BASE + 0;
constexpr uint16_t BKEY_DOUBLE_ZERO = BKEY_SPECIAL_BASE + 1;
constexpr uint16_t BKEY_COMMODORE = BKEY_SPECIAL_BASE + 2;
constexpr uint16_t BKEY_CTRL = BKEY_SPECIAL_BASE + 3;
constexpr uint16_t BKEY_PI = BKEY_SPECIAL_BASE + 4;
constexpr uint16_t BKEY_INSDEL = BKEY_SPECIAL_BASE + 5;
constexpr uint16_t BKEY_CLRHOME = BKEY_SPECIAL_BASE + 6;
constexpr uint16_t BKEY_OFFRVS = BKEY_SPECIAL_BASE + 7;
constexpr uint16_t BKEY_NORMGRAPH = BKEY_SPECIAL_BASE + 8;
constexpr uint16_t BKEY_RUNSTOP = BKEY_SPECIAL_BASE + 9;
constexpr uint16_t BKEY_LEFTARROW_POUND = BKEY_SPECIAL_BASE + 10;
constexpr uint16_t BKEY_CE = BKEY_SPECIAL_BASE + 11;
constexpr uint16_t BKEY_SHIFT_LOCK = BKEY_SPECIAL_BASE + 12;
constexpr uint16_t BKEY_SHIFT = BKEY_SPECIAL_BASE + 13;

constexpr uint16_t BKEY_STATE_COUNT = 0x0300;
uint8_t b_key_source_ref_count[BKEY_STATE_COUNT] = {};
bool b_key_state[BKEY_STATE_COUNT] = {};

// Complete B128/B256 High-Profile matrix map.
//
// scan_index:
//   0..7  = PB0..PB7 = MT8816 X0..X7
//   8..15 = PA0..PA7 = MT8816 X8..X15
//
// return_index:
//   0..5  = PC0..PC5 = MT8816 Y0..Y5
//
// Therefore the matrix coordinates can be passed directly to mt8816_set().

const uint16_t b128_matrix_keys[] = {
  // PC0: F1..F10, cursor/editing keys
  BKEY_HID_BASE + 0x3A,  // F1       PB0 / PC0
  BKEY_HID_BASE + 0x3B,  // F2       PB1 / PC0
  BKEY_HID_BASE + 0x3C,  // F3       PB2 / PC0
  BKEY_HID_BASE + 0x3D,  // F4       PB3 / PC0
  BKEY_HID_BASE + 0x3E,  // F5       PB4 / PC0
  BKEY_HID_BASE + 0x3F,  // F6       PB5 / PC0
  BKEY_HID_BASE + 0x40,  // F7       PB6 / PC0
  BKEY_HID_BASE + 0x41,  // F8       PB7 / PC0
  BKEY_HID_BASE + 0x42,  // F9       PA0 / PC0
  BKEY_HID_BASE + 0x43,  // F10      PA1 / PC0
  BKEY_HID_BASE + 0x51,  // Down     PA2 / PC0
  BKEY_HID_BASE + 0x52,  // Up       PA3 / PC0
  BKEY_CLRHOME,           // Home     PA4 / PC0
  BKEY_OFFRVS,            // RVS      PA5 / PC0
  BKEY_NORMGRAPH,         // Graph    PA6 / PC0
  BKEY_RUNSTOP,           // Run/Stop PA7 / PC0

  // PC1: escape, main number row, cursor/keypad row
  BKEY_HID_BASE + 0x29,  // Escape    PB0 / PC1
  BKEY_HID_BASE + 0x1E,  // 1         PB1 / PC1
  BKEY_HID_BASE + 0x1F,  // 2         PB2 / PC1
  BKEY_HID_BASE + 0x20,  // 3         PB3 / PC1
  BKEY_HID_BASE + 0x21,  // 4         PB4 / PC1
  BKEY_HID_BASE + 0x22,  // 5         PB5 / PC1
  BKEY_HID_BASE + 0x24,  // 7         PB6 / PC1
  BKEY_HID_BASE + 0x25,  // 8         PB7 / PC1
  BKEY_HID_BASE + 0x26,  // 9         PA0 / PC1
  BKEY_HID_BASE + 0x27,  // 0         PA1 / PC1
  BKEY_HID_BASE + 0x2E,  // =         PA2 / PC1
  BKEY_HID_BASE + 0x50,  // Left      PA3 / PC1
  BKEY_NUMPAD_QUESTION,  // Numpad ?  PA4 / PC1
  BKEY_CE,               // CE        PA5 / PC1
  BKEY_HID_BASE + 0x55,  // Numpad *  PA6 / PC1
  BKEY_HID_BASE + 0x54,  // Numpad /  PA7 / PC1

  // PC2: tab/control, alphabet and keypad row
  BKEY_HID_BASE + 0x2B,  // Tab       PB0 / PC2
  BKEY_HID_BASE + 0x14,  // Q         PB1 / PC2
  BKEY_HID_BASE + 0x1A,  // W         PB2 / PC2
  BKEY_HID_BASE + 0x08,  // E         PB3 / PC2
  BKEY_HID_BASE + 0x15,  // R         PB4 / PC2
  BKEY_HID_BASE + 0x23,  // 6         PB5 / PC2
  BKEY_HID_BASE + 0x18,  // U         PB6 / PC2
  BKEY_HID_BASE + 0x0C,  // I         PB7 / PC2
  BKEY_HID_BASE + 0x12,  // O         PA0 / PC2
  BKEY_HID_BASE + 0x2D,  // -         PA1 / PC2
  BKEY_LEFTARROW_POUND,  // <- / pound PA2 / PC2
  BKEY_HID_BASE + 0x4F,  // Right     PA3 / PC2
  BKEY_HID_BASE + 0x5F,  // Numpad 7  PA4 / PC2
  BKEY_HID_BASE + 0x60,  // Numpad 8  PA5 / PC2
  BKEY_HID_BASE + 0x61,  // Numpad 9  PA6 / PC2
  BKEY_HID_BASE + 0x56,  // Numpad -  PA7 / PC2

  // PC3: alphabet and keypad row; PB0 / PC3 is unused
  BKEY_NONE,              // unused    PB0 / PC3
  BKEY_HID_BASE + 0x04,  // A         PB1 / PC3
  BKEY_HID_BASE + 0x16,  // S         PB2 / PC3
  BKEY_HID_BASE + 0x07,  // D         PB3 / PC3
  BKEY_HID_BASE + 0x17,  // T         PB4 / PC3
  BKEY_HID_BASE + 0x1C,  // Y         PB5 / PC3
  BKEY_HID_BASE + 0x0D,  // J         PB6 / PC3
  BKEY_HID_BASE + 0x0E,  // K         PB7 / PC3
  BKEY_HID_BASE + 0x0F,  // L         PA0 / PC3
  BKEY_HID_BASE + 0x13,  // P         PA1 / PC3
  BKEY_HID_BASE + 0x30,  // ]         PA2 / PC3
  BKEY_INSDEL,            // Ins/Del   PA3 / PC3
  BKEY_HID_BASE + 0x5C,  // Numpad 4  PA4 / PC3
  BKEY_HID_BASE + 0x5D,  // Numpad 5  PA5 / PC3
  BKEY_HID_BASE + 0x5E,  // Numpad 6  PA6 / PC3
  BKEY_HID_BASE + 0x57,  // Numpad +  PA7 / PC3

  // PC4: Shift, alphabet/punctuation and keypad row
  BKEY_SHIFT,             // Shift        PB0 / PC4
  BKEY_HID_BASE + 0x1D,  // Z            PB1 / PC4
  BKEY_HID_BASE + 0x1B,  // X            PB2 / PC4
  BKEY_HID_BASE + 0x09,  // F            PB3 / PC4
  BKEY_HID_BASE + 0x0A,  // G            PB4 / PC4
  BKEY_HID_BASE + 0x0B,  // H            PB5 / PC4
  BKEY_HID_BASE + 0x10,  // M            PB6 / PC4
  BKEY_HID_BASE + 0x36,  // ,            PB7 / PC4
  BKEY_HID_BASE + 0x33,  // ;            PA0 / PC4
  BKEY_HID_BASE + 0x2F,  // [            PA1 / PC4
  BKEY_HID_BASE + 0x28,  // Return       PA2 / PC4
  BKEY_COMMODORE,         // Commodore    PA3 / PC4
  BKEY_HID_BASE + 0x59,  // Numpad 1     PA4 / PC4
  BKEY_HID_BASE + 0x5A,  // Numpad 2     PA5 / PC4
  BKEY_HID_BASE + 0x5B,  // Numpad 3     PA6 / PC4
  BKEY_HID_BASE + 0x58,  // Numpad Enter PA7 / PC4

  // PC5: control, alphabet/punctuation and keypad bottom row
  BKEY_CTRL,              // Ctrl      PB0 / PC5
  BKEY_HID_BASE + 0x06,  // C         PB2 / PC5
  BKEY_HID_BASE + 0x19,  // V         PB3 / PC5
  BKEY_HID_BASE + 0x05,  // B         PB4 / PC5
  BKEY_HID_BASE + 0x11,  // N         PB5 / PC5
  BKEY_HID_BASE + 0x2C,  // Space     PB6 / PC5
  BKEY_HID_BASE + 0x37,  // .         PB7 / PC5
  BKEY_HID_BASE + 0x38,  // /         PA0 / PC5
  BKEY_HID_BASE + 0x34,  // '         PA1 / PC5
  BKEY_PI,                // Pi        PA2 / PC5
  BKEY_HID_BASE + 0x62,  // Numpad 0  PA4 / PC5
  BKEY_HID_BASE + 0x63,  // Numpad .  PA5 / PC5
  BKEY_DOUBLE_ZERO        // Numpad 00 PA6 / PC5
};

const uint8_t b128_matrix_scan_index[] = {
  // PC0
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  // PC1
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  // PC2
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  // PC3
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  // PC4
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  // PC5; PB1, PA3, and PA7 are unused positions
  0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14
};

const uint8_t b128_matrix_return_index[] = {
  // PC0
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  // PC1
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  // PC2
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  // PC3
  3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
  // PC4
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
  // PC5
  5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5
};

constexpr uint8_t B128_MATRIX_KEY_COUNT =
    sizeof(b128_matrix_keys) / sizeof(b128_matrix_keys[0]);

static_assert(
    B128_MATRIX_KEY_COUNT ==
        sizeof(b128_matrix_scan_index) / sizeof(b128_matrix_scan_index[0]),
    "B128 matrix key/scan tables differ in size");

static_assert(
    B128_MATRIX_KEY_COUNT ==
        sizeof(b128_matrix_return_index) / sizeof(b128_matrix_return_index[0]),
    "B128 matrix key/return tables differ in size");

struct BKeyEventMap {
  uint16_t first;
  uint16_t second;
};

BKeyEventMap b_key_source_map[256] = {};
bool b_key_source_map_valid[256] = {};

// ---------------------------------------------------------------------------
// Logging / matrix lookup
// ---------------------------------------------------------------------------

void print_hex_byte(uint8_t value) {
  if (value < 0x10) {
    Serial.print('0');
  }
  Serial.print(value, HEX);
}

const char *hid_usage_name(uint8_t usage) {
  if (usage >= 0x04 && usage <= 0x1D) {
    static char name[2];
    name[0] = static_cast<char>('A' + usage - 0x04);
    name[1] = '\0';
    return name;
  }

  if (usage >= 0x1E && usage <= 0x27) {
    static const char digits[] = "1234567890";
    static char name[2];
    name[0] = digits[usage - 0x1E];
    name[1] = '\0';
    return name;
  }

  switch (usage) {
    case 0x28: return "ENTER";
    case 0x29: return "ESC";
    case 0x2A: return "BACKSPACE";
    case 0x2B: return "TAB";
    case 0x2C: return "SPACE";
    case 0x2D: return "-";
    case 0x2E: return "=";
    case 0x2F: return "[";
    case 0x30: return "]";
    case 0x31: return "\\";
    case 0x32: return "#";
    case 0x33: return ";";
    case 0x34: return "'";
    case 0x35: return "`";
    case 0x36: return ",";
    case 0x37: return ".";
    case 0x38: return "/";
    case 0x39: return "CAPS LOCK";
    case 0x3A: return "F1";
    case 0x3B: return "F2";
    case 0x3C: return "F3";
    case 0x3D: return "F4";
    case 0x3E: return "F5";
    case 0x3F: return "F6";
    case 0x40: return "F7";
    case 0x41: return "F8";
    case 0x42: return "F9";
    case 0x43: return "F10";
    case 0x44: return "F11";
    case 0x45: return "F12";
    case 0x46: return "PRINT SCREEN";
    case 0x47: return "SCROLL LOCK";
    case 0x48: return "PAUSE";
    case 0x49: return "INSERT";
    case 0x4A: return "HOME";
    case 0x4B: return "PAGE UP";
    case 0x4C: return "DELETE";
    case 0x4D: return "END";
    case 0x4E: return "PAGE DOWN";
    case 0x4F: return "RIGHT ARROW";
    case 0x50: return "LEFT ARROW";
    case 0x51: return "DOWN ARROW";
    case 0x52: return "UP ARROW";
    case 0x53: return "NUM LOCK";
    case 0x54: return "KEYPAD /";
    case 0x55: return "KEYPAD *";
    case 0x56: return "KEYPAD -";
    case 0x57: return "KEYPAD +";
    case 0x58: return "KEYPAD ENTER";
    case 0x59: return "KEYPAD 1";
    case 0x5A: return "KEYPAD 2";
    case 0x5B: return "KEYPAD 3";
    case 0x5C: return "KEYPAD 4";
    case 0x5D: return "KEYPAD 5";
    case 0x5E: return "KEYPAD 6";
    case 0x5F: return "KEYPAD 7";
    case 0x60: return "KEYPAD 8";
    case 0x61: return "KEYPAD 9";
    case 0x62: return "KEYPAD 0";
    case 0x63: return "KEYPAD .";
    case 0x64: return "ISO EXTRA KEY";
    case 0xE0: return "LEFT CTRL";
    case 0xE1: return "LEFT SHIFT";
    case 0xE2: return "LEFT ALT";
    case 0xE3: return "LEFT GUI";
    case 0xE4: return "RIGHT CTRL";
    case 0xE5: return "RIGHT SHIFT";
    case 0xE6: return "RIGHT ALT";
    case 0xE7: return "RIGHT GUI";
    default: return "UNKNOWN HID USAGE";
  }
}

const char *consumer_usage_name(uint16_t usage) {
  switch (usage) {
    case 0x00B0: return "PLAY";
    case 0x00B5: return "NEXT TRACK";
    case 0x00B6: return "PREVIOUS TRACK";
    case 0x00CD: return "PLAY/PAUSE";
    case 0x00E2: return "MUTE";
    case 0x00E9: return "VOLUME UP";
    case 0x00EA: return "VOLUME DOWN";
    case 0x0183: return "MEDIA SELECT COMPUTER";
    default: return "UNKNOWN CONSUMER USAGE";
  }
}

void print_us_iso_name(uint8_t usage, bool shifted, bool caps) {
  if (usage >= 0x04 && usage <= 0x1D) {
    char value = static_cast<char>('a' + usage - 0x04);
    if (shifted ^ caps) {
      value = static_cast<char>(value - 'a' + 'A');
    }
    Serial.print(value);
    return;
  }

  if (usage >= 0x1E && usage <= 0x27) {
    static const char unshifted[] = "1234567890";
    static const char shifted_values[] = "!@#$%^&*()";
    Serial.print((shifted ? shifted_values : unshifted)[usage - 0x1E]);
    return;
  }

  switch (usage) {
    case 0x2D: Serial.print(shifted ? '_' : '-'); return;
    case 0x2E: Serial.print(shifted ? '+' : '='); return;
    case 0x2F: Serial.print(shifted ? '{' : '['); return;
    case 0x30: Serial.print(shifted ? '}' : ']'); return;
    case 0x31: Serial.print(shifted ? '|' : '\\'); return;
    case 0x32: Serial.print(shifted ? '~' : '#'); return;
    case 0x33: Serial.print(shifted ? ':' : ';'); return;
    case 0x34: Serial.print(shifted ? '"' : '\''); return;
    case 0x35: Serial.print(shifted ? '~' : '`'); return;
    case 0x36: Serial.print(shifted ? '>' : '<'); return;
    case 0x37: Serial.print(shifted ? '>' : '.'); return;
    case 0x38: Serial.print(shifted ? '?' : '/'); return;
    case 0x64: Serial.print(shifted ? '>' : '<'); return;
    default: Serial.print(hid_usage_name(usage)); return;
  }
}

void print_b128_logical_key_name(uint16_t key) {
  switch (key) {
    case BKEY_NUMPAD_QUESTION: Serial.print(F("?")); return;
    case BKEY_DOUBLE_ZERO: Serial.print(F("00")); return;
    case BKEY_COMMODORE: Serial.print(F("Commodore")); return;
    case BKEY_CTRL: Serial.print(F("Ctrl")); return;
    case BKEY_PI: Serial.print(F("Pi")); return;
    case BKEY_INSDEL: Serial.print(F("InsDel")); return;
    case BKEY_CLRHOME: Serial.print(F("ClrHome")); return;
    case BKEY_OFFRVS: Serial.print(F("OffRvs")); return;
    case BKEY_NORMGRAPH: Serial.print(F("NormGraph")); return;
    case BKEY_RUNSTOP: Serial.print(F("RunStop")); return;
    case BKEY_LEFTARROW_POUND: Serial.print(F("<-")); return;
    case BKEY_CE: Serial.print(F("CE")); return;
    case BKEY_SHIFT_LOCK: Serial.print(F("SHIFT LOCK (unused)")); return;
    case BKEY_SHIFT: Serial.print(F("SHIFT")); return;
    default:
      if (key >= BKEY_HID_BASE && key < BKEY_HID_BASE + 0x100) {
        print_us_iso_name(static_cast<uint8_t>(key - BKEY_HID_BASE), false, false);
      } else {
        Serial.print(F("<unknown B128/B256 key>"));
      }
      return;
  }
}

bool get_b128_matrix_lines(uint16_t key, uint8_t &scan_index,
                        uint8_t &return_index) {
  for (uint8_t i = 0; i < B128_MATRIX_KEY_COUNT; ++i) {
    if (b128_matrix_keys[i] == key) {
      scan_index = b128_matrix_scan_index[i];
      return_index = b128_matrix_return_index[i];
      return true;
    }
  }
  return false;
}

bool print_b128_matrix_lines(uint16_t key) {
  uint8_t scan_index;
  uint8_t return_index;

  if (!get_b128_matrix_lines(key, scan_index, return_index)) {
    return false;
  }

  if (scan_index < 8) {
    Serial.print(F("PB"));
    Serial.print(scan_index);
  } else {
    Serial.print(F("PA"));
    Serial.print(scan_index - 8);
  }

  Serial.print(F(" PC"));
  Serial.print(return_index);

  if (debug_log_conv >= 2) {
    Serial.print(F(" -> X"));
    Serial.print(scan_index);
    Serial.print(F(" Y"));
    Serial.print(return_index);
  }

  return true;
}

void log_b128_conversion(uint16_t key, bool pressed) {
  if (debug_log_conv == 0 || !pressed) {
    return;
  }

  print_b128_logical_key_name(key);

  if (debug_log_conv >= 2) {
    Serial.print(F(" : "));
    if (!print_b128_matrix_lines(key)) {
      Serial.print(F("<matrix lines not mapped>"));
    }
  }

  Serial.println();
}

void log_hid_event(uint8_t usage, bool pressed) {
  if (!debug_log_hid) {
    return;
  }

  Serial.print(F("HID 0x"));
  print_hex_byte(usage);
  Serial.print(F(" ("));
  Serial.print(hid_usage_name(usage));
  Serial.print(F(") : "));
  Serial.println(pressed ? F("on") : F("off"));
}

void log_consumer_event(uint16_t usage, bool pressed) {
  if (!debug_log_hid) {
    return;
  }

  Serial.print(F("HID Consumer 0x"));
  print_hex_byte(static_cast<uint8_t>(usage >> 8));
  print_hex_byte(static_cast<uint8_t>(usage));
  Serial.print(F(" ("));
  Serial.print(consumer_usage_name(usage));
  Serial.print(F(") : "));
  Serial.println(pressed ? F("on") : F("off"));
}

void log_us_iso_event(uint8_t usage, bool pressed,
                   bool current_shifted, bool current_caps) {
  if (!debug_log_us_iso || (!pressed && debug_log_us_iso < 2)) {
    return;
  }

  bool shifted = current_shifted;
  bool caps = current_caps;

  if (pressed) {
    us_iso_shift_at_press[usage] = shifted;
    us_iso_caps_at_press[usage] = caps;
  } else {
    shifted = us_iso_shift_at_press[usage];
    caps = us_iso_caps_at_press[usage];
  }

  print_us_iso_name(usage, shifted, caps);
  Serial.print(F(" : "));
  Serial.println(pressed ? F("on") : F("off"));
}

// ---------------------------------------------------------------------------
// B128 logical-key -> MT8816 actuation
// ---------------------------------------------------------------------------

void set_b128_logical_key_state(uint16_t key, bool pressed) {
  if (key >= BKEY_STATE_COUNT || key == BKEY_NONE) {
    return;
  }

  b_key_state[key] = pressed;
  log_b128_conversion(key, pressed);

  uint8_t scan_index;
  uint8_t return_index;

  if (!get_b128_matrix_lines(key, scan_index, return_index)) {
    return;
  }

  // The indices are physical MT8816 X/Y line numbers.
  // mt8816_set() translates the X line number into the AX pin encoding.
  mt8816_set(scan_index, return_index, pressed);
}

void emit_b128_logical_key(uint16_t key, bool pressed) {
  if (key == BKEY_NONE || key >= BKEY_STATE_COUNT) {
    return;
  }

  if (pressed) {
    if (b_key_source_ref_count[key] < 0xFF) {
      ++b_key_source_ref_count[key];
    }

    if (b_key_source_ref_count[key] == 1) {
      set_b128_logical_key_state(key, true);
    }
  } else if (b_key_source_ref_count[key] != 0) {
    --b_key_source_ref_count[key];

    if (b_key_source_ref_count[key] == 0) {
      set_b128_logical_key_state(key, false);
    }
  }
}

uint32_t pack_b_key_event_map(uint16_t first, uint16_t second) {
  return (static_cast<uint32_t>(first) << 16) | second;
}

uint32_t map_us_iso_to_b128(uint8_t usage, bool shifted) {
  switch (usage) {
    case 0x53:  // Num Lock -> B128/B256 numpad '?'
      return pack_b_key_event_map(BKEY_NUMPAD_QUESTION, BKEY_NONE);

    case 0x62:  // Keypad 0; Shift+keypad 0 -> B128/B256 '00'
      return pack_b_key_event_map(
          shifted ? BKEY_DOUBLE_ZERO :
                    static_cast<uint16_t>(BKEY_HID_BASE + usage),
          BKEY_NONE);

    case 0xE3:  // Left GUI -> Commodore
    case 0xE7:  // Right GUI -> Commodore
      return pack_b_key_event_map(BKEY_COMMODORE, BKEY_NONE);

    case 0xE0:  // Left Ctrl -> Ctrl
    case 0xE4:  // Right Ctrl -> Ctrl
      return pack_b_key_event_map(BKEY_CTRL, BKEY_NONE);

    case 0x31:  // Backslash -> Pi
      return pack_b_key_event_map(BKEY_PI, BKEY_NONE);

    case 0x2A:  // Backspace -> InsDel
    case 0x4C:  // Delete -> same physical InsDel key
      return pack_b_key_event_map(BKEY_INSDEL, BKEY_NONE);

    case 0x49:  // Insert -> Shift+InsDel
      return pack_b_key_event_map(BKEY_INSDEL, BKEY_SHIFT);

    case 0x4A:  // Home -> ClrHome
    case 0x45:  // F12 -> ClrHome
      return pack_b_key_event_map(BKEY_CLRHOME, BKEY_NONE);

    case 0x46:  // Print Screen -> OffRvs
      return pack_b_key_event_map(BKEY_OFFRVS, BKEY_NONE);

    case 0x47:  // Scroll Lock -> NormGraph
      return pack_b_key_event_map(BKEY_NORMGRAPH, BKEY_NONE);

    case 0x48:  // Pause -> RunStop
      return pack_b_key_event_map(BKEY_RUNSTOP, BKEY_NONE);

    case 0x44:  // F11 -> left-arrow/pound key
    case 0x35:  // US backtick -> left-arrow/pound key
      return pack_b_key_event_map(BKEY_LEFTARROW_POUND, BKEY_NONE);

    case 0x4D:  // End -> CE
      return pack_b_key_event_map(BKEY_CE, BKEY_NONE);

    case 0x39:  // handled as a Shift-Lock toggle in process_b128_key_event()
      return pack_b_key_event_map(BKEY_NONE, BKEY_NONE);

    case 0xE1:  // Left Shift
    case 0xE5:  // Right Shift
      return pack_b_key_event_map(BKEY_SHIFT, BKEY_NONE);

    default:
      return pack_b_key_event_map(
          static_cast<uint16_t>(BKEY_HID_BASE + usage), BKEY_NONE);
  }
}

void process_b128_key_event(uint8_t usage, bool pressed, bool shifted) {
  // The B128 Shift-Lock key mechanically latches the same matrix contact as Shift (PB0 / PC4).
  // USB Caps Lock is therefore implemented as a toggle source for BKEY_SHIFT rather than as a separate matrix position.
  //
  // caps_lock_state is toggled on the Caps Lock rising edge in process_hid_state() before this function is called.
  // Reference counting keeps this correct if a real USB Shift key is held at the same time.
  if (usage == 0x39) {
    if (pressed) {
      emit_b128_logical_key(BKEY_SHIFT, caps_lock_state);
    }
    return;
  }

  if (pressed) {
    const uint32_t packed_mapping = map_us_iso_to_b128(usage, shifted);

    const BKeyEventMap mapping = {
        static_cast<uint16_t>(packed_mapping >> 16),
        static_cast<uint16_t>(packed_mapping & 0xFFFF)
    };

    b_key_source_map[usage] = mapping;
    b_key_source_map_valid[usage] = true;

    // For a synthetic modifier combination, assert Shift before InsDel.
    emit_b128_logical_key(mapping.second, true);
    emit_b128_logical_key(mapping.first, true);
    return;
  }

  if (!b_key_source_map_valid[usage]) {
    return;
  }

  const BKeyEventMap mapping = b_key_source_map[usage];

  // Release the key before releasing its synthetic modifier.
  emit_b128_logical_key(mapping.first, false);
  emit_b128_logical_key(mapping.second, false);
  b_key_source_map_valid[usage] = false;
}

// ---------------------------------------------------------------------------
// HID report processing
// ---------------------------------------------------------------------------

void process_hid_state(const bool *current) {
  // Toggle Caps Lock only on its rising edge.
  if (current[0x39] && (!hid_state_valid || !hid_pressed[0x39])) {
    caps_lock_state = !caps_lock_state;
  }

  const bool current_shifted = current[0xE1] || current[0xE5];
  const bool current_caps = caps_lock_state;

  for (uint16_t usage = 0; usage < 256; ++usage) {
    const bool was_pressed = hid_state_valid && hid_pressed[usage];
    const bool is_pressed = current[usage];

    if (was_pressed == is_pressed) {
      continue;
    }

    log_hid_event(static_cast<uint8_t>(usage), is_pressed);
    log_us_iso_event(static_cast<uint8_t>(usage), is_pressed,
                  current_shifted, current_caps);
    process_b128_key_event(static_cast<uint8_t>(usage), is_pressed,
                        current_shifted);

    hid_pressed[usage] = is_pressed;
  }

  for (uint16_t usage = 0; usage < 256; ++usage) {
    hid_pressed[usage] = current[usage];
  }

  hid_state_valid = true;
}

void process_consumer_state(const bool *current) {
  for (uint16_t usage = 0; usage < 256; ++usage) {
    const bool was_pressed = consumer_state_valid && consumer_pressed[usage];
    const bool is_pressed = current[usage];

    if (was_pressed == is_pressed) {
      continue;
    }

    log_consumer_event(usage, is_pressed);
    consumer_pressed[usage] = is_pressed;
  }

  for (uint16_t usage = 0; usage < 256; ++usage) {
    consumer_pressed[usage] = current[usage];
  }

  consumer_state_valid = true;
}

void decode_hid_report(const uint8_t *hid, uint8_t hid_length) {
  bool current[256] = {};
  bool recognized = false;

  // CH9350L Consumer Control report:
  // report ID 0x02 followed by a 16-bit Consumer usage, low byte first.
  if (hid_length == 3 && hid[0] == 0x02) {
    const uint16_t usage = static_cast<uint16_t>(hid[1]) |
                           (static_cast<uint16_t>(hid[2]) << 8);

    if (usage < 256) {
      current[usage] = true;
    }

    process_consumer_state(current);
    return;
  }

  // Standard 8-byte boot keyboard report without report ID:
  // modifier, reserved, six simultaneous key usages.
  if (hid_length == 8) {
    const uint8_t modifier = hid[0];

    for (uint8_t bit = 0; bit < 8; ++bit) {
      if (modifier & (1u << bit)) {
        current[0xE0 + bit] = true;
      }
    }

    for (uint8_t i = 2; i < 8; ++i) {
      if (hid[i] != 0) {
        current[hid[i]] = true;
      }
    }

    recognized = true;
  }

  // Standard 8-byte boot keyboard report with a report ID.
  if (hid_length == 9) {
    const uint8_t modifier = hid[1];

    for (uint8_t bit = 0; bit < 8; ++bit) {
      if (modifier & (1u << bit)) {
        current[0xE0 + bit] = true;
      }
    }

    for (uint8_t i = 3; i < 9; ++i) {
      if (hid[i] != 0) {
        current[hid[i]] = true;
      }
    }

    recognized = true;
  }

  // Observed CH9350L length byte 0x14: 17 HID bytes plus identifier, sequence and checksum.
  // The HID bytes are report ID 0x0C, modifier byte and a 15-byte NKRO bitmap.
  if (hid_length == 17 && hid[0] == 0x0C) {
    const uint8_t modifier = hid[1];

    for (uint8_t bit = 0; bit < 8; ++bit) {
      if (modifier & (1u << bit)) {
        current[0xE0 + bit] = true;
      }
    }

    for (uint8_t byte_index = 2; byte_index < 17; ++byte_index) {
      for (uint8_t bit = 0; bit < 8; ++bit) {
        if (hid[byte_index] & (1u << bit)) {
          const uint16_t usage =
              HID_NKRO_USAGE_BASE +
              static_cast<uint16_t>(byte_index - 2) * 8 + bit;

          if (usage < 256) {
            current[usage] = true;
          }
        }
      }
    }

    recognized = true;
  }

  if (debug_log_hid && !recognized) {
    Serial.print(F("HID: unsupported report length="));
    Serial.print(hid_length);

    if (hid_length > 0) {
      Serial.print(F(" id=0x"));
      print_hex_byte(hid[0]);
    }

    Serial.println();
  }

  if (recognized) {
    process_hid_state(current);
  }
}

// ---------------------------------------------------------------------------
// Raw CH9350L framing
// ---------------------------------------------------------------------------

void print_raw_changes(const uint8_t *raw, uint8_t raw_length) {
  if (!previous_raw_valid || previous_raw_length != raw_length) {
    if (debug_log_raw) {
      Serial.println(F("RAW baseline captured; press and release one key."));
    }
  } else {
    for (uint8_t i = 0; i < raw_length; ++i) {
      if (previous_raw[i] == raw[i]) {
        continue;
      }

      if (debug_log_raw) {
        Serial.print(F("RAW["));
        Serial.print(i);
        Serial.print(F("]: "));
        print_hex_byte(previous_raw[i]);
        Serial.print(F(" -> "));
        print_hex_byte(raw[i]);

        if (previous_raw[i] == 0 && raw[i] != 0) {
          Serial.print(F(" : on"));
        } else if (previous_raw[i] != 0 && raw[i] == 0) {
          Serial.print(F(" : off"));
        } else {
          Serial.print(F(" : changed"));
        }

        Serial.println();
      }
    }
  }

  for (uint8_t i = 0; i < raw_length; ++i) {
    previous_raw[i] = raw[i];
  }

  previous_raw_length = raw_length;
  previous_raw_valid = true;
}

void handle_ch9350_frame() {
  if (ch_command == 0x82) {
    // The status request is diagnostic here and does not change key state.
    if (debug_log_raw) {
      Serial.print(F("CH status: "));
      print_hex_byte(ch_data[0]);
      Serial.println();
    }
    return;
  }

  // For 0x88/0x83 frames, the length block is:
  // identifier + raw key data + sequence number + checksum.
  if (ch_data_length < 3) {
    return;
  }

  const uint8_t identifier = ch_data[0];
  const uint8_t hid_length = ch_data_length - 3;
  const uint8_t sequence = ch_data[ch_data_length - 2];
  const uint8_t checksum = ch_data[ch_data_length - 1];
  const uint8_t *hid = &ch_data[1];

  uint8_t calculated_checksum = sequence;

  for (uint8_t i = 0; i < hid_length; ++i) {
    calculated_checksum += hid[i];
  }

  if (debug_log_raw) {
    Serial.print(F("CH key frame 0x"));
    print_hex_byte(ch_command);
    Serial.print(F(" id=0x"));
    print_hex_byte(identifier);
    Serial.print(F(" seq=0x"));
    print_hex_byte(sequence);
    Serial.print(F(" checksum="));

    if (calculated_checksum == checksum) {
      Serial.print(F("OK"));
    } else {
      Serial.print(F("BAD expected 0x"));
      print_hex_byte(calculated_checksum);
      Serial.print(F(" got 0x"));
      print_hex_byte(checksum);
    }

    Serial.println();

    Serial.print(F("RAW: "));
    for (uint8_t i = 0; i < hid_length; ++i) {
      print_hex_byte(hid[i]);
      Serial.print(' ');
    }
    Serial.println();
  }

  // Ignore corrupt frames before they can change any key state.
  if (calculated_checksum != checksum) return;
  print_raw_changes(hid, hid_length);
  decode_hid_report(hid, hid_length);
}

void reset_ch_parser() {
  ch_parser_state = WAIT_HEADER_57;
  ch_data_length = 0;
  ch_data_index = 0;
}

void process_ch9350_byte(uint8_t value) {
  switch (ch_parser_state) {
    case WAIT_HEADER_57:
      if (value == 0x57) {
        ch_parser_state = WAIT_HEADER_AB;
      }
      break;

    case WAIT_HEADER_AB:
      if (value == 0xAB) {
        ch_parser_state = WAIT_COMMAND;
      } else if (value != 0x57) {
        reset_ch_parser();
      }
      break;

    case WAIT_COMMAND:
      ch_command = value;

      if (ch_command == 0x82) {
        ch_parser_state = READ_STATUS;
      } else if (ch_command == 0x88 || ch_command == 0x83) {
        ch_parser_state = READ_LENGTH;
      } else {
        reset_ch_parser();
      }
      break;

    case READ_STATUS:
      ch_data[0] = value;
      handle_ch9350_frame();
      reset_ch_parser();
      break;

    case READ_LENGTH:
      ch_data_length = value;

      if (ch_data_length < 3 || ch_data_length > CH_MAX_DATA_LENGTH) {
        reset_ch_parser();
      } else {
        ch_data_index = 0;
        ch_parser_state = READ_DATA;
      }
      break;

    case READ_DATA:
      ch_data[ch_data_index++] = value;

      if (ch_data_index >= ch_data_length) {
        handle_ch9350_frame();
        reset_ch_parser();
      }
      break;
  }
}

void log_ch9350_bytes() {
  while (Serial1.available() > 0) {
    process_ch9350_byte(static_cast<uint8_t>(Serial1.read()));
  }
}

// ---------------------------------------------------------------------------
// Arduino entry points
// ---------------------------------------------------------------------------

void setup() {
  setup_mt8816();

  // Serial is the Mega USB debug connection at 500000 baud.
  Serial.begin(500000);

  // Serial1 is dedicated to the CH9350L.
  Serial1.begin(CH9350_BAUD);

  Serial.println(F("B128/B256 CH9350L + MT8816 keyboard adapter ready"));
  Serial.println(F("MT8816 reset complete; all crosspoints open"));
}

void loop() {
  log_ch9350_bytes();
}
