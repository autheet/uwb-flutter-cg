import pandas as pd
import plotly.express as px
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import savgol_filter
import plotly.express as px

with open('positionsdaten.txt') as f:
    # lese zeile für zeile ein nach dem format 1.0881285612492124, 3.1703530754570766
    lines = [line.rstrip('\n') for line in f]
    # convert to x: andy y: values
    lines = [line.split(', ') for line in lines]

# map lines from x and y to a dictionary
pos = [{'x': float(i[0]), 'y': float(i[1])} for i in lines]
plt.scatter(x=[i['x'] for i in pos], y=[i['y'] for i in pos])

# mean of the x and y values
mean_x = np.mean([i['x'] for i in pos])
mean_y = np.mean([i['y'] for i in pos])

print(f"Mittelpunkt X: {mean_x}, Mittelpunkt Y: {mean_y}")

# berechne standardabweichung
std_x = np.std([i['x'] for i in pos])
std_y = np.std([i['y'] for i in pos])

print(f"Standardabweichung X: {std_x}, Standardabweichung Y: {std_y}")

plt.axhline(y=mean_y, color='blue', linestyle='--')
plt.axvline(x=mean_x, color='red', linestyle='--')

plt.title('Bestimmung der Position zu drei Entwicklungskits mittels Trilateration')
plt.xlabel('X-Position')
plt.ylabel('Y-Position')

plt.show()