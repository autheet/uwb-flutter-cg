import pandas as pd
import plotly.express as px
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import savgol_filter

with open('messwerte_10m.txt') as f:
    lines = [float(line.rstrip('\n')) for line in f]

# map lines to a dictionary

#lines = [{'Datenpunkte': i, 'Distanz in Meter': lines[i]} for i in range(len(lines))]

#df = pd.DataFrame(lines)
#fig = px.line(df, x="Datenpunkte", y="Distanz in Meter", title='Messung der Distanz zum Zubehör')

#fig.show()

r = 300
range = lines[0:r]
x = np.linspace(0, r, r)

# take 30 points and smooth them
#y_filter = savgol_filter(range, r, 3)

# get mean of the smoothed values
#mean = np.mean(y_filter)
mean2 = np.mean(range)

plt.plot(x, range)
#plt.plot(x, y_filter, color='red')

plt.axhline(y=mean2, color='green', linestyle='--')
print(mean2)

plt.title('Messung der Distanz zum Zubehör (10m)')
plt.xlabel('Datenpunkte')
plt.ylabel('Distanz in Meter')

plt.show()