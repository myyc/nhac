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
from pathlib import Path

# Configuration
DEFAULT_SVG = "assets/icons/nhac.svg"
FOREGROUND_SVG = "assets/icons/fgnhac.svg"  # White play buttons only

# Linux icon sizes
LINUX_SIZES = [64, 128, 256, 512]


class IconGenerator:
    def __init__(self, svg_path):
        self.project_root = Path(__file__).parent
        self.svg_path = Path(svg_path) if svg_path else self.project_root / DEFAULT_SVG
        self.foreground_svg_path = self.project_root / FOREGROUND_SVG
        self.android_res = self.project_root / "android/app/src/main/res"
        self.linux_icons = self.project_root / "linux/icons"
        self.temp_dir = self.project_root / "temp_icons"

        # Check that required SVG files exist
        if not self.foreground_svg_path.exists():
            raise FileNotFoundError(f"Foreground SVG file not found: {self.foreground_svg_path}")

        print(f"Using SVG: {self.svg_path}")
        print(f"Using foreground SVG: {self.foreground_svg_path}")

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
    
    def setup(self):
        """Create necessary directories."""
        self.temp_dir.mkdir(exist_ok=True)
        self.linux_icons.mkdir(parents=True, exist_ok=True)
    
    def cleanup(self):
        """Remove temporary files."""
        if self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)
    
    def convert_svg_to_png_path(self, svg_path, size, output_path):
        """Convert specific SVG file to PNG at given size."""
        if not svg_path.exists():
            raise FileNotFoundError(f"SVG file not found: {svg_path}")

        # Read and validate SVG content
        with open(svg_path, 'r') as f:
            svg_content = f.read()

        if not svg_content.strip().startswith('<?xml') and not svg_content.strip().startswith('<svg'):
            raise ValueError(f"Invalid SVG content in {svg_path}")

        if self.svg_converter == 'rsvg-convert':
            cmd = [
                'rsvg-convert',
                '-a',  # Keep aspect ratio
                '-w', str(size),
                '-h', str(size),
                str(svg_path),
                '-o', str(output_path)
            ]
        elif self.svg_converter == 'inkscape':
            cmd = [
                'inkscape',
                str(svg_path),
                '--export-type=png',
                f'--export-filename={output_path}',
                f'--export-width={size}',
                f'--export-height={size}'
            ]
        else:  # magick
            cmd = [
                'magick',
                '-density', '300',
                '-background', 'none',
                str(svg_path),
                '-resize', f'{size}x{size}',
                str(output_path)
            ]

        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        if result.stderr:
            print(f"Warning: {result.stderr}")

        return output_path

    def create_notification_icon(self):
        """Create notification icon using the foreground SVG."""
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

            # Use foreground SVG directly (already white and centered)
            output_path = output_dir / "ic_notification.png"
            self.convert_svg_to_png_path(self.foreground_svg_path, size, output_path)

        print("  ✅ Notification icons created!")

    def generate_linux_icons(self):
        """Generate Linux desktop icons."""
        print("\n🐧 Generating Linux icons...")
        
        for size in LINUX_SIZES:
            # Create icons with old naming (for compatibility)
            output_path = self.linux_icons / f"nhac-{size}.png"
            self.convert_svg_to_png_path(self.svg_path, size, output_path)
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

    def verify_results(self):
        """Verify the generated icons are correct."""
        print("\n🔍 Verifying generated icons...")

        # Check key files exist
        files_to_check = [
            ("mipmap-hdpi/ic_launcher_foreground.png", "Foreground"),
            ("mipmap-hdpi/ic_launcher_monochrome.png", "Monochrome"),
            ("drawable-hdpi/ic_notification.png", "Notification"),
        ]

        for file_path, name in files_to_check:
            full_path = self.android_res / file_path
            if full_path.exists():
                print(f"  {name}: ✅ Created")
            else:
                print(f"  {name}: ⚠️ Missing")

        # Check colors.xml
        colors_file = self.android_res / "values" / "colors.xml"
        if colors_file.exists():
            content = colors_file.read_text()
            if self.background_color in content:
                print(f"  Background color: ✅ {self.background_color}")
            else:
                print(f"  Background color: ⚠️ Not set correctly")
    
    def run(self):
        """Generate Linux and notification icons only."""
        try:
            self.setup()

            print("=" * 50)
            print("🎨 Linux & Notification Icon Generator")
            print("=" * 50)

            # Generate Linux icons (using circular nhac.svg)
            self.generate_linux_icons()

            # Generate Android notification icons (using fgnhac.svg)
            self.create_notification_icon()

            print("\n" + "=" * 50)
            print("✅ Linux and notification icons generated successfully!")
            print("=" * 50)
            print("\nIcon configuration:")
            print(f"  • Linux Icons: Using nhac.svg (circular icon)")
            print(f"  • Android Notification: Using fgnhac.svg (white play buttons only)")
            print(f"  • Launcher Icons: Generated by flutter_launcher_icons")
            
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