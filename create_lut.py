from PIL import Image

INPUT_FILE = 'bbr_color.txt'
OUTPUT_FILE = 'resources/bbr_lut.png'
LUT_SIZE = 256  
TEMP_MIN = 1000.0 
TEMP_MAX = 40000.0 

def parse_bbr_data(filename):
    data_points = []
    print(f"Reading data from {filename}...")
    with open(filename, 'r') as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            
            if "2deg" not in line:
                continue

            parts = line.strip().split()
            try:
                temp = float(parts[0])
                r_float = float(parts[6])
                g_float = float(parts[7])
                b_float = float(parts[8])
                data_points.append((temp, (r_float, g_float, b_float)))
            except (ValueError, IndexError):
                print(f"Could not parse line: {line}")
                continue
    
    print(f"Successfully parsed {len(data_points)} data points.")
    return sorted(data_points) 

def lerp(v0, v1, t):
    return v0 + t * (v1 - v0)

def lerp_color(color1, color2, t):
    r = lerp(color1[0], color2[0], t)
    g = lerp(color1[1], color2[1], t)
    b = lerp(color1[2], color2[2], t)
    return (r, g, b)

def create_lut(data_points):
    lut_pixels = []
    print(f"Generating LUT with {LUT_SIZE} pixels for range {TEMP_MIN}K to {TEMP_MAX}K...")

    for i in range(LUT_SIZE):
        progress = i / (LUT_SIZE - 1)
        target_temp = lerp(TEMP_MIN, TEMP_MAX, progress)

        p1 = None
        p2 = None
        for point in data_points:
            if point[0] <= target_temp:
                p1 = point
            if point[0] >= target_temp:
                p2 = point
                break
        
        if not p1: p1 = data_points[0]
        if not p2: p2 = data_points[-1]

        if p1[0] == p2[0]:
            final_color = p1[1]
        else:
            interp_t = (target_temp - p1[0]) / (p2[0] - p1[0])
            final_color = lerp_color(p1[1], p2[1], interp_t)
            
        r_byte = int(max(0, min(255, final_color[0] * 255)))
        g_byte = int(max(0, min(255, final_color[1] * 255)))
        b_byte = int(max(0, min(255, final_color[2] * 255)))
        
        lut_pixels.append((r_byte, g_byte, b_byte))
        
    return lut_pixels

def save_lut_as_image(pixels, filename):
    img = Image.new('RGB', (LUT_SIZE, 1))
    img.putdata(pixels)
    img.save(filename)
    print(f"Successfully saved LUT to {filename}")

if __name__ == "__main__":
    parsed_data = parse_bbr_data(INPUT_FILE)
    if parsed_data:
        lut_data = create_lut(parsed_data)
        save_lut_as_image(lut_data, OUTPUT_FILE)
