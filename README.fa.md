# openwrt-usb-extroot-swap

<p align="center">
  <a href="README.md">🇬🇧 English</a>
  &nbsp;|&nbsp;
  <strong><img src="https://commons.wikimedia.org/wiki/Special:Redirect/file/State_flag_of_the_Imperial_State_of_Iran_(with_standardized_lion_and_sun).svg?width=48" width="28" alt="پرچم شیر و خورشید ایران"> فارسی</strong>
</p>

[![بررسی اسکریپت‌ها](https://github.com/MehrooExplains/openwrt-usb-extroot-swap/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/MehrooExplains/openwrt-usb-extroot-swap/actions/workflows/shellcheck.yml)

این پروژه یک **فلش USB متصل به OpenWrt** را به‌صورت خودکار آماده می‌کند تا هم Swap داشته باشید و هم تقریباً تمام فضای باقی‌مانده فلش به **حافظه قابل استفاده OpenWrt برای نصب پکیج‌ها و برنامه‌ها** تبدیل شود.

> **هشدار بسیار مهم:** فلش انتخاب‌شده به‌طور کامل پارتیشن‌بندی و فرمت می‌شود و تمام اطلاعات آن پاک خواهد شد. اسکریپت تا زمانی که دقیقاً عبارت `ERASE /dev/sdX` را برای همان دیسک وارد نکنید، پارتیشن‌بندی را شروع نمی‌کند.

## انتخاب اندازه Swap

هنگام اجرا این منو نمایش داده می‌شود:

```text
1) 256 MiB
2) 512 MiB
3) 1 GiB
4) 2 GiB
5) مقدار دلخواه / Custom
```

با گزینه ۵ می‌توانید مقدار Swap را دستی وارد کنید. مثال:

```text
768       -> 768 MiB
768M      -> 768 MiB
1.5G      -> 1536 MiB
3G        -> 3072 MiB
```

اگر فقط عدد وارد کنید، مقدار بر حسب MiB در نظر گرفته می‌شود. Installer اندازه واردشده را بررسی می‌کند و اگر بعد از ساخت Swap فضای کافی برای Extroot باقی نماند، ادامه نمی‌دهد.

بعد از انتخاب Swap، **تمام فضای باقی‌مانده فلش** به یک پارتیشن `ext4` برای Extroot تبدیل می‌شود.

## ساختار نهایی فلش

```text
فلش USB
   |
   +-- پارتیشن 1 -> Linux Swap
   |
   +-- پارتیشن 2 -> ext4 -> /overlay (Extroot)
```

بعد از Reboot، Firmware اصلی OpenWrt همچنان از حافظه داخلی دستگاه بوت می‌شود، ولی بخش Writable یا همان `/overlay` از فلش USB استفاده می‌کند. در نتیجه فضای نصب پکیج‌ها و برنامه‌های OpenWrt عملاً به اندازه پارتیشن Extroot روی فلش افزایش پیدا می‌کند.

این روش بر اساس Extroot استاندارد OpenWrt ساخته شده است: نصب `block-mount`، ساخت فایل‌سیستم ext4، کپی Overlay فعلی روی حافظه خارجی و تنظیم `/etc/config/fstab` با UUID پارتیشن‌ها.

## ایمنی

اسکریپت برای جلوگیری از پاک شدن دیسک اشتباه:

- دیسک‌های USB را به‌صورت خودکار شناسایی می‌کند.
- دیسکی که به `/`، `/rom`، `/overlay`، `/rwm` یا Boot مربوط باشد انتخاب نمی‌کند.
- دیسکی که Swap فعال روی آن باشد کنار گذاشته می‌شود.
- مدل و ظرفیت USB را قبل از فرمت نشان می‌دهد.
- اگر بیش از یک USB متصل باشد، از کاربر می‌خواهد دیسک را انتخاب کند.
- برای شروع فرمت باید مسیر کامل دیسک را در عبارت تأیید وارد کنید.
- قبل از تغییر، از `/etc/config/fstab` بکاپ می‌گیرد.

به‌عبارت دیگر، قرار نیست یک اسکریپت «خودکار» با اعتمادبه‌نفس کامل هارد اشتباه را قربانی کند. این سطح از خودباوری را به انسان‌ها واگذار می‌کنیم.

## پکیج‌های مورد نیاز

Installer تشخیص می‌دهد OpenWrt از `apk` استفاده می‌کند یا `opkg` و ابزارهای لازم را نصب می‌کند:

```text
block-mount
e2fsprogs
parted
swap-utils
kmod-usb-storage
kmod-fs-ext4
```

پکیج `swap-utils` ابزار `mkswap` را فراهم می‌کند و OpenWrt برای Extroot به `block-mount` نیاز دارد.

## پیش‌نیازهای نصب

- روتر OpenWrt با امکان بازیابی در صورت بروز مشکل
- دسترسی SSH با کاربر root
- یک حافظه USB اختصاصی که پاک‌شدن کامل آن مجاز باشد
- اینترنت فعال برای نصب پکیج‌ها
- فضای کافی برای Swap انتخابی و حداقل ۱۲۸ MiB برای Extroot
- پشتیبان به‌روز از تنظیمات مهم روتر

پیشنهاد می‌شود پیش از اجرا، حافظه‌های USB نامرتبط را جدا کنید. اسکریپت چندین
بررسی ایمنی انجام می‌دهد، اما مسئولیت انتخاب نهایی دیسک و تأیید عملیات پاک‌سازی
با کاربر است.

## فایل‌ها و تنظیمات تغییریافته

Installer دو پارتیشن GPT می‌سازد، آن‌ها را به Swap و ext4 فرمت می‌کند، Overlay
فعلی را کپی می‌کند و Sectionهای زیر را در UCI می‌سازد:

```text
fstab.usb_extroot
fstab.usb_swap
fstab.rwm       (اگر Overlay داخلی قابل تشخیص باشد)
```

State و نسخه‌های پشتیبان در مسیر زیر ذخیره می‌شوند:

```text
/etc/openwrt-usb-extroot-swap/
```

## نصب سریع

اسکریپت نصب در ریشه پروژه با نام `install.sh` قرار دارد. برای نصب مستقیم روی OpenWrt فقط این دستور را اجرا کنید:

```sh
wget -O /tmp/openwrt-usb-extroot-swap-install.sh \
  https://raw.githubusercontent.com/MehrooExplains/openwrt-usb-extroot-swap/main/install.sh && \
sh /tmp/openwrt-usb-extroot-swap-install.sh
```

اگر `wget` روی Firmware شما موجود نیست ولی `curl` دارید:

```sh
curl -fL \
  https://raw.githubusercontent.com/MehrooExplains/openwrt-usb-extroot-swap/main/install.sh \
  -o /tmp/openwrt-usb-extroot-swap-install.sh && \
sh /tmp/openwrt-usb-extroot-swap-install.sh
```

### اجرای فایل به‌صورت دستی

اگر Repository را قبلاً دانلود یا Clone کرده‌اید:

```sh
chmod +x install.sh
./install.sh
```

Installer به‌ترتیب:

1. OpenWrt و Package Manager را تشخیص می‌دهد.
2. ابزارهای لازم را نصب می‌کند.
3. فلش‌های USB امن برای انتخاب را پیدا می‌کند.
4. اندازه Swap را از شما می‌پرسد.
5. جدول پارتیشن GPT می‌سازد.
6. پارتیشن اول را Swap می‌کند.
7. پارتیشن دوم را با تمام فضای باقی‌مانده `ext4` می‌کند.
8. Overlay فعلی OpenWrt را روی Extroot کپی می‌کند.
9. Swap و Extroot را با UUID در `fstab` ثبت می‌کند.
10. برای Extroot مقدار `delay_root=15` قرار می‌دهد تا USBهای کندتر هنگام Boot فرصت شناسایی داشته باشند.

در پایان می‌توانید همان لحظه Reboot کنید یا بعداً دستی Reboot کنید.

## بررسی بعد از Reboot

```sh
df -h / /overlay
cat /proc/swaps
block info
```

باید فضای `/` و `/overlay` تقریباً برابر فضای باقی‌مانده فلش باشد و Swap نیز در `/proc/swaps` دیده شود.

اگر `health-check.sh` کنار Installer موجود باشد، دستور زیر نیز نصب می‌شود:

```sh
openwrt-usb-extroot-health
```

## غیرفعال کردن بدون پاک کردن فلش

```sh
chmod +x disable.sh
./disable.sh
```

این اسکریپت فقط Entryهای Extroot و Swap ساخته‌شده توسط پروژه را غیرفعال می‌کند و فلش را دوباره فرمت نمی‌کند.

اگر Overlay داخلی در `/rwm` در دسترس نباشد، می‌توانید روتر را یک بار بدون فلش بوت کنید و Entry مربوط به Extroot را از `/etc/config/fstab` حذف کنید.

## نکات مهم

- Swap جای RAM واقعی را نمی‌گیرد.
- استفاده دائمی از فلش USB بی‌کیفیت برای Overlay و Swap می‌تواند عمر فلش را کاهش دهد.
- Extroot برای بوت به شناسایی به‌موقع حافظه خارجی وابسته است.
- قبل از استفاده روی روتر دوردست یا حیاتی، فرآیند Boot و Recovery را حداقل یک بار تست کنید.

## رفع اشکال و بازیابی

### USB شناسایی نمی‌شود

```sh
dmesg | tail -n 80
block info
ls -l /sys/class/block/
```

پورت USB، منبع تغذیه، قاب یا فلش دیگری را امتحان کنید. بعضی حافظه‌ها به
`kmod-usb-storage-uas` نیاز دارند که Installer در صورت موجودبودن نصب می‌کند.

### روتر بوت می‌شود ولی Extroot فعال نیست

```sh
block info
uci show fstab
logread | grep -Ei 'block|mount|extroot|overlay'
df -h / /overlay
```

UUID پارتیشن ext4 باید با `fstab.usb_extroot.uuid` یکسان باشد. برای حافظه‌های
کند ممکن است لازم باشد مقدار `fstab.@global[0].delay_root` افزایش پیدا کند.

### روتر با USB بوت نمی‌شود

روتر را خاموش، USB را جدا و دستگاه را از حافظه داخلی بوت کنید. سپس Sectionهای
ساخته‌شده در fstab را بررسی یا حذف کنید. پیش از استفاده روی روتر دوردست، یک
روش بازیابی مانند Failsafe، Serial Console یا Firmware Recovery آماده داشته باشید.

### Swap فعال نیست

```sh
cat /proc/swaps
uci show fstab.usb_swap
block info
```

UUID ثبت‌شده برای Swap باید با UUID پارتیشن Swap روی USB یکسان باشد.

## بررسی توسعه

تمام اسکریپت‌ها برای سازگاری OpenWrt با POSIX `sh` نوشته شده‌اند:

```sh
shellcheck -s sh install.sh health-check.sh disable.sh
sh -n install.sh health-check.sh disable.sh
```

GitHub Actions همین بررسی را هنگام تغییر اسکریپت‌ها یا workflow اجرا می‌کند.

## منابع

- OpenWrt Extroot configuration: https://openwrt.org/docs/guide-user/additional-software/extroot_configuration
- OpenWrt Fstab configuration: https://openwrt.org/docs/guide-user/storage/fstab

## License

MIT License.
