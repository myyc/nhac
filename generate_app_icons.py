#!/usr/bin/env python3
"""
Generate all app icons (Android adaptive icons and Linux icons) from a single SVG source.
This creates foreground, background, and monochrome layers for Android's adaptive icon system,
as well as Linux desktop icons.

Usage: python3 generate_app_icons.py [path/to/icon.svg]
"""

import subprocess
import sys
import shutil
import re
from pathlib import Path
from PIL import Image
import numpy as np

# Configuration
DEFAULT_SVG = "assets/icons/nhac.svg"
ICON_SCALE = 0.45  # Icon takes up 45% of canvas (safe zone)
ICON_OFFSET_X = 0.03  # 3% right offset for visual balance

# Android icon sizes (foreground/background are 1.5x the launcher icon size)
ANDROID_SIZES = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432
}

# Linux icon sizes
LINUX_SIZES = [64, 128, 256, 512]

# macOS icon sizes
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]


class IconGenerator:
    def __init__(self, svg_path):
        self.project_root = Path(__file__).parent
        self.svg_path = Path(svg_path) if svg_path else self.project_root / DEFAULT_SVG
        self.android_res = self.project_root / "android/app/src/main/res"
        self.linux_icons = self.project_root / "linux/icons"
        self.macos_assets = self.project_root / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
        self.temp_dir = self.project_root / "temp_icons"
        
        if not self.svg_path.exists():
            raise FileNotFoundError(f"SVG file not found: {self.svg_path}")
        
        print(f"Using SVG: {self.svg_path}")
        
        # Extract the fill color from the SVG
        self.original_color = self.extract_svg_color()
        self.background_color = self.original_color if self.original_color else "#3A7BE0"
        print(f"Detected icon color: {self.background_color}")
        
        # Check for available SVG converters
        self.svg_converter = self.detect_svg_converter()
        print(f"Using SVG converter: {self.svg_converter}")
    
    def detect_svg_converter(self):
        """Detect the best available SVG to PNG converter."""
        converters = [
            ('rsvg-convert', ['rsvg-convert', '--version']),
            ('inkscape', ['inkscape', '--version']),
            ('magick', ['magick', '-version'])
        ]
        
        for name, check_cmd in converters:
            try:
                subprocess.run(check_cmd, capture_output=True, check=True)
                return name
            except:
                continue
        
        # Default to magick as it's most likely to be available
        return 'magick'
    
    def extract_svg_color(self):
        """Extract the fill color from the SVG."""
        with open(self.svg_path, 'r') as f:
            svg_content = f.read()
        
        # Look for fill color in various formats
        # Try hex color first
        hex_match = re.search(r'fill[:\s]*["\']?(#[0-9a-fA-F]{6})', svg_content)
        if hex_match:
            return hex_match.group(1).upper()
        
        # Try rgb format
        rgb_match = re.search(r'fill[:\s]*["\']?rgb\((\d+),\s*(\d+),\s*(\d+)\)', svg_content)
        if rgb_match:
            r, g, b = rgb_match.groups()
            return f"#{int(r):02X}{int(g):02X}{int(b):02X}"
        
        return None
    
    def setup(self):
        """Create necessary directories."""
        self.temp_dir.mkdir(exist_ok=True)
        self.linux_icons.mkdir(parents=True, exist_ok=True)
    
    def cleanup(self):
        """Remove temporary files."""
        if self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)
    
    def convert_svg_to_png_native(self, size, output_path):
        """Convert SVG to PNG using the best available converter, ensuring square output."""
        # First convert to a temp file to get the actual image
        temp_output = self.temp_dir / f"temp_{size}.png"
        
        if self.svg_converter == 'rsvg-convert':
            # First render at the desired size (will maintain aspect ratio)
            cmd = [
                'rsvg-convert',
                '-a',  # Keep aspect ratio
                '-w', str(size),
                '-h', str(size),
                str(self.svg_path),
                '-o', str(temp_output)
            ]
        elif self.svg_converter == 'inkscape':
            cmd = [
                'inkscape',
                str(self.svg_path),
                '--export-type=png',
                f'--export-filename={temp_output}',
                f'--export-width={size}',
                f'--export-height={size}'
            ]
        else:  # magick
            cmd = [
                'magick',
                '-density', '300',
                '-background', 'none',
                str(self.svg_path),
                '-resize', f'{size}x{size}',  # Resize maintaining aspect ratio
                str(temp_output)
            ]
        
        subprocess.run(cmd, check=True, capture_output=True)
        
        # Now pad to square using PIL
        img = Image.open(temp_output).convert("RGBA")
        
        # Create a new square image with transparent background
        square_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        
        # Calculate position to center the image
        img_w, img_h = img.size
        x = (size - img_w) // 2
        y = (size - img_h) // 2
        
        # Paste the image centered
        square_img.paste(img, (x, y), img)
        
        # Save the square image
        square_img.save(output_path, 'PNG')
        
        return output_path
    
    def create_white_foreground(self, size_name, size):
        """Create white foreground icon for Android preserving exact shape."""
        output_dir = self.android_res / f"mipmap-{size_name}"
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Convert SVG to PNG at higher resolution for quality
        temp_png = self.temp_dir / f"temp_{size_name}.png"
        self.convert_svg_to_png_native(int(size * 2), temp_png)
        
        # Load and process the image
        img = Image.open(temp_png).convert("RGBA")
        
        # Get actual content bounds
        bbox = img.getbbox()
        if bbox:
            # Crop to content
            content = img.crop(bbox)
            
            # Calculate scaling to fit in safe zone
            w, h = content.size
            aspect = w / h
            target_size = int(size * ICON_SCALE)
            
            if aspect > 1:
                new_w = target_size
                new_h = int(target_size / aspect)
            else:
                new_h = target_size
                new_w = int(target_size * aspect)
            
            # Resize with high quality
            content = content.resize((new_w, new_h), Image.Resampling.LANCZOS)
            
            # Create transparent canvas
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            
            # Center with offset
            x = (size - new_w) // 2 + int(size * ICON_OFFSET_X)
            y = (size - new_h) // 2
            
            # Paste preserving alpha channel
            canvas.paste(content, (x, y), content)
            
            # Convert to white while preserving shape
            data = np.array(canvas)
            
            # Process each pixel
            for i in range(data.shape[0]):
                for j in range(data.shape[1]):
                    r, g, b, a = data[i, j]
                    if a > 0:  # Has opacity
                        # Make it white, preserve alpha for antialiasing
                        data[i, j] = [255, 255, 255, a]
            
            # Save final foreground
            output_path = output_dir / "ic_launcher_foreground.png"
            result = Image.fromarray(data.astype(np.uint8))
            result.save(output_path, 'PNG')
        
        # Clean up
        temp_png.unlink()
        
        return output_path
    
    def create_monochrome_icon(self, size_name, size):
        """Create monochrome icon with alpha variations for Android 13+ theming."""
        output_dir = self.android_res / f"mipmap-{size_name}"
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Generate monochrome from the original colored SVG, not the white foreground
        # Convert SVG to PNG at higher resolution
        temp_png = self.temp_dir / f"mono_temp_{size_name}.png"
        self.convert_svg_to_png_native(int(size * 2), temp_png)
        
        # Load and process the image
        img = Image.open(temp_png).convert("RGBA")
        
        # Get actual content bounds
        bbox = img.getbbox()
        if bbox:
            # Crop to content
            content = img.crop(bbox)
            
            # Calculate scaling to fit in safe zone
            w, h = content.size
            aspect = w / h
            target_size = int(size * ICON_SCALE)
            
            if aspect > 1:
                new_w = target_size
                new_h = int(target_size / aspect)
            else:
                new_h = target_size
                new_w = int(target_size * aspect)
            
            # Resize with high quality
            content = content.resize((new_w, new_h), Image.Resampling.LANCZOS)
            
            # Create transparent canvas
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            
            # Center with offset
            x = (size - new_w) // 2 + int(size * ICON_OFFSET_X)
            y = (size - new_h) // 2
            
            # Paste preserving alpha channel
            canvas.paste(content, (x, y), content)
            
            # Convert to monochrome (black with alpha)
            data = np.array(canvas)
            mono_data = np.zeros_like(data)
            
            # Process each pixel - use the original colors to create alpha variations
            for i in range(data.shape[0]):
                for j in range(data.shape[1]):
                    r, g, b, a = data[i, j]
                    if a > 0:
                        # For monochrome, just make it black with full opacity
                        # Android will handle the tinting
                        mono_data[i, j] = [0, 0, 0, a]
            
            # Save monochrome
            output_path = output_dir / "ic_launcher_monochrome.png"
            result = Image.fromarray(mono_data.astype(np.uint8))
            result.save(output_path, 'PNG')
        
        # Clean up
        temp_png.unlink()
        
        return output_path
    
    def create_background_resources(self):
        """Create Android background color resource."""
        colors_dir = self.android_res / "values"
        colors_dir.mkdir(parents=True, exist_ok=True)
        
        colors_file = colors_dir / "colors.xml"
        if colors_file.exists():
            # Read existing content
            with open(colors_file, 'r') as f:
                content = f.read()
            
            # Update or add the launcher background color
            if 'ic_launcher_background' in content:
                # Replace existing color
                content = re.sub(
                    r'<color name="ic_launcher_background">#[0-9A-Fa-f]{6}</color>',
                    f'<color name="ic_launcher_background">{self.background_color}</color>',
                    content
                )
            else:
                # Add new color
                content = content.replace('</resources>', 
                    f'    <color name="ic_launcher_background">{self.background_color}</color>\n</resources>')
            
            with open(colors_file, 'w') as f:
                f.write(content)
        else:
            with open(colors_file, 'w') as f:
                f.write(f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{self.background_color}</color>
</resources>''')
    
    def create_adaptive_icon_xml(self):
        """Create Android adaptive icon XML configurations."""
        configs = [
            ('mipmap-anydpi-v26', False),  # Android 8+ without monochrome
            ('mipmap-anydpi-v33', True),   # Android 13+ with monochrome
        ]
        
        for dir_name, include_monochrome in configs:
            anydpi_dir = self.android_res / dir_name
            anydpi_dir.mkdir(parents=True, exist_ok=True)
            
            # Create ic_launcher.xml
            monochrome_line = '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n' if include_monochrome else ''
            xml_content = f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
{monochrome_line}</adaptive-icon>'''
            
            (anydpi_dir / "ic_launcher.xml").write_text(xml_content)
            (anydpi_dir / "ic_launcher_round.xml").write_text(xml_content)
    
    def create_launch_background(self):
        """Update Android launch/splash screen background."""
        for drawable_dir in ['drawable', 'drawable-v21']:
            dir_path = self.android_res / drawable_dir
            if dir_path.exists():
                launch_bg = dir_path / "launch_background.xml"
                if launch_bg.exists():
                    content = launch_bg.read_text()
                    # Make background transparent
                    content = re.sub(
                        r'android:drawable="@android:color/\w+"',
                        'android:drawable="@android:color/transparent"',
                        content
                    )
                    content = re.sub(
                        r'android:drawable="\?android:\w+"',
                        'android:drawable="@android:color/transparent"',
                        content
                    )
                    launch_bg.write_text(content)
    
    def create_notification_icon(self):
        """Create notification icon (white on transparent) for Android status bar."""
        print("  Creating notification icons...")
        
        # Notification icons need to be in drawable folders at specific sizes
        notification_sizes = {
            'drawable-mdpi': 24,
            'drawable-hdpi': 36,
            'drawable-xhdpi': 48,
            'drawable-xxhdpi': 72,
            'drawable-xxxhdpi': 96
        }
        
        for folder, size in notification_sizes.items():
            output_dir = self.android_res / folder
            output_dir.mkdir(parents=True, exist_ok=True)
            
            # Convert SVG to PNG
            temp_png = self.temp_dir / f"notif_{size}.png"
            self.convert_svg_to_png_native(int(size * 2), temp_png)
            
            # Load and process
            img = Image.open(temp_png).convert("RGBA")
            
            # Get bounds and crop
            bbox = img.getbbox()
            if bbox:
                content = img.crop(bbox)
                
                # Scale to fit the notification icon size (with some padding)
                w, h = content.size
                aspect = w / h
                target_size = int(size * 0.8)  # 80% to leave padding
                
                if aspect > 1:
                    new_w = target_size
                    new_h = int(target_size / aspect)
                else:
                    new_h = target_size
                    new_w = int(target_size * aspect)
                
                content = content.resize((new_w, new_h), Image.Resampling.LANCZOS)
                
                # Create canvas
                canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
                
                # Center the icon
                x = (size - new_w) // 2
                y = (size - new_h) // 2
                canvas.paste(content, (x, y), content)
                
                # Convert to white (notification icons must be white)
                data = np.array(canvas)
                for i in range(data.shape[0]):
                    for j in range(data.shape[1]):
                        r, g, b, a = data[i, j]
                        if a > 0:
                            # Make it white, keep alpha
                            data[i, j] = [255, 255, 255, a]
                
                # Save as ic_notification
                output_path = output_dir / "ic_notification.png"
                result = Image.fromarray(data.astype(np.uint8))
                result.save(output_path, 'PNG')
            
            # Clean up
            temp_png.unlink()
        
        print("  ✅ Notification icons created!")
    
    def generate_android_icons(self):
        """Generate all Android adaptive icon assets."""
        print("\n📱 Generating Android icons...")
        
        for size_name, size in ANDROID_SIZES.items():
            print(f"  Creating {size_name} icons (size: {size}px)...")
            
            # Create white foreground with proper shape
            self.create_white_foreground(size_name, size)
            
            # Create monochrome from foreground
            self.create_monochrome_icon(size_name, size)
        
        # Create notification icon
        self.create_notification_icon()
        
        # Create background and XML resources
        self.create_background_resources()
        self.create_adaptive_icon_xml()
        self.create_launch_background()
        
        print("  ✅ Android icons complete!")
    
    def generate_linux_icons(self):
        """Generate Linux desktop icons."""
        print("\n🐧 Generating Linux icons...")
        
        for size in LINUX_SIZES:
            # Create icons with old naming (for compatibility)
            output_path = self.linux_icons / f"nhac-{size}.png"
            self.convert_svg_to_png_native(size, output_path)
            print(f"  Created: {output_path}")
            
            # Also create icons with flatpak naming convention
            flatpak_path = self.linux_icons / f"dev.myyc.nhac-{size}.png"
            shutil.copy(output_path, flatpak_path)
            print(f"  Created: {flatpak_path}")
        
        # Create default icons without size suffix
        shutil.copy(self.linux_icons / "nhac-256.png", self.linux_icons / "nhac.png")
        shutil.copy(self.linux_icons / "nhac-256.png", self.linux_icons / "dev.myyc.nhac.png")
        print(f"  Created: default icons (256x256)")
        
        # Copy SVG with both names
        shutil.copy(self.svg_path, self.linux_icons / "nhac.svg")
        shutil.copy(self.svg_path, self.linux_icons / "dev.myyc.nhac.svg")
        
        # Create desktop file
        desktop_file = self.project_root / "linux" / "nhac.desktop"
        desktop_content = '''[Desktop Entry]
Version=1.0
Type=Application
Name=Nhac
Comment=Flutter music player application
Exec=nhac
Icon=dev.myyc.nhac
Terminal=false
Categories=AudioVideo;Audio;Music;Player;
StartupWMClass=Nhac'''
        desktop_file.write_text(desktop_content)
        
        print("  ✅ Linux icons complete!")
    
    def generate_macos_icons(self):
        """Generate macOS app icons."""
        print("\n🍎 Generating macOS icons...")
        
        # Ensure the directory exists
        self.macos_assets.mkdir(parents=True, exist_ok=True)
        
        for size in MACOS_SIZES:
            output_path = self.macos_assets / f"app_icon_{size}.png"
            self.convert_svg_to_png_native(size, output_path)
            print(f"  Created: {output_path.name} ({size}x{size})")
        
        print("  ✅ macOS icons complete!")
    
    def verify_results(self):
        """Verify the generated icons are correct."""
        print("\n🔍 Verifying generated icons...")
        
        # Check a sample foreground
        fg_path = self.android_res / "mipmap-hdpi" / "ic_launcher_foreground.png"
        if fg_path.exists():
            img = Image.open(fg_path)
            data = np.array(img)
            
            non_transparent = np.sum(data[:,:,3] > 0)
            if non_transparent > 0:
                # Check if it's white
                mask = data[:,:,3] > 0
                pixels = data[mask]
                is_white = np.mean(pixels[:, :3]) > 250
                
                print(f"  Foreground: {'✅ White' if is_white else '⚠️ Not white'}")
                print(f"  Non-transparent pixels: {non_transparent}")
            else:
                print("  ⚠️ Foreground is empty!")
        
        # Check monochrome
        mono_path = self.android_res / "mipmap-hdpi" / "ic_launcher_monochrome.png"
        if mono_path.exists():
            img = Image.open(mono_path)
            data = np.array(img)
            non_transparent = np.sum(data[:,:,3] > 0)
            print(f"  Monochrome: {'✅' if non_transparent > 0 else '⚠️ Empty'} ({non_transparent} pixels)")
        
        # Check notification icon
        notif_path = self.android_res / "drawable-hdpi" / "ic_notification.png"
        if notif_path.exists():
            print(f"  Notification icon: ✅ Created")
        
        # Check colors.xml
        colors_file = self.android_res / "values" / "colors.xml"
        if colors_file.exists():
            content = colors_file.read_text()
            if self.background_color in content:
                print(f"  Background color: ✅ {self.background_color}")
            else:
                print(f"  Background color: ⚠️ Not set correctly")
    
    def run(self):
        """Generate all icons."""
        try:
            self.setup()
            
            print("=" * 50)
            print("🎨 App Icon Generator")
            print("=" * 50)
            
            self.generate_android_icons()
            self.generate_linux_icons()
            self.generate_macos_icons()
            self.verify_results()
            
            print("\n" + "=" * 50)
            print("✅ All icons generated successfully!")
            print("=" * 50)
            print("\nIcon configuration:")
            print(f"  • Background: {self.background_color} (extracted from SVG)")
            print(f"  • Foreground: White icon")
            print(f"  • Notification: White icon on transparent")
            print(f"  • Scale: {int(ICON_SCALE * 100)}% of canvas")
            print(f"  • Monochrome: Black with alpha variations for Material You")
            
        finally:
            self.cleanup()


def main():
    svg_path = sys.argv[1] if len(sys.argv) > 1 else None
    
    try:
        generator = IconGenerator(svg_path)
        generator.run()
    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        print(f"\nUsage: {sys.argv[0]} [path/to/icon.svg]")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()