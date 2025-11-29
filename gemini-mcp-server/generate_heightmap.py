from PIL import Image
import numpy as np

# Create a 513x513 grayscale image
width, height = 513, 513
# Create a numpy array with a simple gradient
array = np.zeros((height, width), dtype=np.uint8)
for y in range(height):
    for x in range(width):
        # A simple hill in the middle
        distance_to_center = np.sqrt((x - width/2)**2 + (y - height/2)**2)
        # Normalize distance to 0-1
        normalized_distance = distance_to_center / (np.sqrt(2) * width/2)
        # Invert so center is high, edges are low, and scale to 0-255
        value = 255 * (1 - normalized_distance)
        array[y, x] = int(value)


img = Image.fromarray(array, 'L')
img.save('terrain/heightmap.png')
print("Heightmap generated.")
