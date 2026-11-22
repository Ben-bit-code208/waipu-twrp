# BT-Fernbedienung in TWRP – Recherche & Plan

Stand: 2026-11-22

## Ergebnis der Recherche

Es gibt **keinen fertigen BT-HID-Treiber für TWRP 11 / Amlogic / MT7663**, den
man einfach einbinden könnte. Gefunden wurden nur Bausteine:

- [CoreELEC/linux-amlogic `btmtksdio.c`](https://github.com/CoreELEC/linux-amlogic/blob/5.15.196_20260225/drivers/bluetooth/btmtksdio.c)
  – Kernel-Treiber, keine Recovery-Integration.
- [CoreELEC/remotes](https://github.com/CoreELEC/remotes) +
  [Wiki: Bluetooth-Remotes](http://wiki.coreelec.org/remote:rr_bluetooth)
  – BlueZ im Userspace, nicht in TWRP.
- [abrasive/tinyhidd](https://github.com/abrasive/tinyhidd) – BTstack + UHID,
  kein BlueZ/D-Bus/Kernel-BT.
- [bluekitchen/btstack `hid_host_demo.c`](https://github.com/bluekitchen/btstack/blob/master/example/hid_host_demo.c)
  – Classic-HID-Host mit Boot-Protocol-Fallback.
- [zampierilucas/kindle-hid-passthrough](https://github.com/zampierilucas/kindle-hid-passthrough)
  – Userspace-BT → UHID.

## Bewertung der Wege

| Weg | Bewertung | Grund |
|---|---|---|
| Fluoride / `system/bt` nativ | ❌ verwerfen | HID-Host hängt an `com.android.bluetooth`, JNI und HIDL-HAL. Kein Standalone-Daemon für Recovery. |
| BlueZ + Key-Konvertierung | ⚠️ machbar, aber schwerer | Braucht GLib ≥ 2.28 + D-Bus ≥ 1.6. Wichtig: `UserspaceHID=true` setzen ([input.conf](https://raw.githubusercontent.com/bluez/bluez/5.55/profiles/input/input.conf)), sonst wäre Kernel-`CONFIG_BT_HIDP` nötig. |
| minimale Mgmt/L2CAP → UHID-Brücke | ✅ empfohlen | Nutzt vorhandenes `CONFIG_UHID` / `CONFIG_HID_GENERIC`; kein `HIDP`, kein D-Bus, kein GLib. Boot-Protokoll reicht für die Tastatur-Fernbedienung. |

`CONFIG_BT_HIDP` fehlt im Stock-Kernel und kann ohne Kernel-Source nicht
nachgebaut werden – Userspace-HID umgeht das.

## Bereits lokal bereitgestellte Dateien

Unter `recovery/root/` im Device-Tree (sowohl im Source-Tree als auch im
Ausgangsverzeichnis):

```text
vendor/lib/modules/btmtksdio.ko          326440 B
vendor/lib/modules/sdio_bt.ko             31296 B
vendor/lib/modules/wlan_mt7663_sdio.ko  3397976 B
vendor/firmware/mt7663_patch_e2_hdr.bin  278558 B
vendor/firmware/bt_mt7663.cfg              1015 B
vendor/firmware/EEPROM_MT7663.bin          1536 B
vendor/usr/keylayout/Vendor_2d01_Product_c006.kl  1730 B
system/usr/keylayout/Vendor_2d01_Product_c006.kl  1730 B
vendor/etc/bluetooth/bt_vendor.conf        271 B
```

`aml_sdio.ko` existiert auf dem Gerät **nicht** – `init.amlogic.bluetooth.rc`
verweist darauf, aber das Modul ist nicht ausgeliefert. Die Init-Skizze unten
lässt es deshalb weg.

**Hinweis:** Das sind proprietäre Vendor-Blobs. Nur lokal zum Bauen nutzen,
nicht in ein öffentliches XDA-Attachment legen.

## Init-Skizze (NOCH NICHT AKTIVIERT)

Die folgenden Zeilen sind ein Entwurf für `init.recovery.amlogic.rc`. Sie
werden erst eingebaut, wenn die Brücke existiert und HCI-Bring-up geklappt hat.

```rc
on early-init
    mkdir /vendor 0755 root root
    mkdir /vendor/firmware 0755 root root
    mkdir /vendor/lib/modules 0755 root root
    mkdir /data/misc/bluetooth 0700 root root
    chmod 0666 /dev/uhid
    write /sys/module/firmware_class/parameters/path /vendor/firmware

on init
    # Reihenfolge: WLAN/BT teilen sich SDIO
    insmod /vendor/lib/modules/wlan_mt7663_sdio.ko
    insmod /vendor/lib/modules/sdio_bt.ko
    insmod /vendor/lib/modules/btmtksdio.ko
    setprop vendor.sys.mtkbtdriver true
    setprop vendor.sys.amlbtsdiodriver true

service btremote /vendor/bin/bt-hid-bridge
    class late_start
    user root
    group root net_admin bluetooth
    seclabel u:r:recovery:s0
    oneshot
    disabled
```

Statt `import /vendor/etc/init/bluetooth.rc` lieber explizite `insmod`-Zeilen:
die Stock-RC setzt Properties, die in der Recovery nicht ausgewertet werden.

## Pairing-Key

Android speichert den Link-Key in `/data/misc/bluedroid/bt_config.conf`
(`LinkKey`, `LinkKeyType`, `PinLength`). Bei FBE/BFU ohne Entschlüsselung ist
die Datei in TWRP nicht lesbar → Key **vorher** extrahieren und in die Ramdisk
legen. Siehe [Android-Forensics-Artikel](https://www.androidforensics.org/en/artifacts/bluetooth-bt-config).

Für BlueZ: `/var/lib/bluetooth/<adapter>/<remote>/info`, Sektion `[LinkKey]`
mit `Key=` (32 Hex-Zeichen), `Type=`, `PINLength=`
([BlueZ settings storage](https://bluez.readthedocs.io/en/latest/settings-storage/)).
Für die Mgmt-API: `Load Link Keys (0x0012)`, Key-Type `0x00`–`0x08`
([mgmt-api.txt](https://raw.githubusercontent.com/bluez/bluez/5.55/doc/mgmt-api.txt)).

**Falle:** Die Adapter-MAC muss zur gespeicherten MAC passen, sonst wird der
Key verworfen.

## Kleinste Brücke (empfohlen)

1. HCI-Bring-up: Module + Firmware laden, `hci0` muss erscheinen.
2. Mgmt-Socket: `Powered`, `Pairable`, ggf. `Load Link Keys` (`CAP_NET_ADMIN`).
3. L2CAP connect auf PSM `0x11` (HID Control) / `0x13` (Interrupt).
4. Boot-Protokoll-Reports parsen → `UHID_CREATE2` / `UHID_INPUT` an `/dev/uhid`.
5. Keylayout `Vendor_2d01_Product_c006.kl` bleibt aktiv (bereits abgelegt).

## Fallstricke

- **SELinux:** Recovery meist permissive; falls nicht: `seclabel u:r:recovery:s0`
  plus Regeln für `/dev/uhid`, Mgmt-Socket und L2CAP (`net_admin`).
- **/data-Verschlüsselung:** sieht oben.
- **Firmware-Pfad:** ohne `/vendor`-Mount `firmware_class.path` explizit setzen.
- **UHID-Rechte:** `/dev/uhid` muss beschreibbar sein.
- **Probe-Order MT7663:** `wlan_mt7663_sdio.ko` vor `btmtksdio.ko` laden,
  sonst bleibt `hci0` weg.
- **Kein Java-Framework:** Fluoride/HID-Host scheitert an `com.android.bluetooth`
  + JNI – deshalb verwerfen.

## Empfohlene Reihenfolge

1. **HCI-Bring-up zuerst**: Module + Firmware + `hci0` verifizieren. Scheitert
   das, ist alles andere obsolet.
2. **Mgmt/L2CAP/UHID-Brücke** im Boot-Protokoll (kleinste Version: nur
   `UHID_INPUT`, keine Langzeit-Keys).
3. **Pairing-Key** aus entschlüsseltem `bt_config.conf` injizieren.
4. **BlueZ nur**, falls die Brücke nicht reicht und D-Bus/GLib verfügbar
   gemacht werden kann (`UserspaceHID=true`!).
5. **Fluoride nicht versuchen.**

Realistisch ist das ein Build von Grund auf, kein Einbinden eines fertigen
Treibers. Die Hürde ist nicht HID, sondern das SDIO/Firmware-Bring-up des
MT7663 im Recovery-Kernel.
