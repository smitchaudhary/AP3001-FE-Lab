a = 1

def print_for_point(x, y, point_number):
    for i in range(len(x)):
            print("Point(%d) = {%d, %d, 0, 1.0};"%(point_number+i, x[i], y[i]))
            print("//+")

def print_for_line(array, point_number):
    aaa = []
    for i in range(len(array)):
        aaa.append(point_number+i)
    print(aaa)
x_eurasia = []
y_eurasia = []

while a:
    x_eurasia.append(int(input()))
    y_eurasia.append(-int(input()))
