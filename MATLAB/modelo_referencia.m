% modelo_referencia.m
% Genera in.txt y ref.txt para el testbench del FIR
% REQUIERE que 'c' y 'S' existan

Fs = 320;
Fruido = 80;
N = numel(c);
Q = round(log2(S));   % Convertir a entero

n = 0:599;
t = n / Fs;

x = round( 500 + 250./(1+exp(-(t-1.10)/0.05)) + 120*sin(2*pi*Fruido*t + 0.7) );

xe = [zeros(1,N) x];
y = zeros(1,numel(x));
for k = 1:numel(x)
    acc = sum( int64(c) .* int64( fliplr(xe(k : k+N-1)) ) );
    y(k) = double( acc / int64(2^Q) );   % División en lugar de bitshift
end

fid = fopen('in.txt','w');
fprintf(fid,'%d\n',x);
fclose(fid);

fid = fopen('ref.txt','w');
fprintf(fid,'%d\n',y);
fclose(fid);

fprintf('Vectores generados: %d muestras\n', numel(x));
fprintf('Rizado a la entrada: %d codigos\n', max(x(60:380))-min(x(60:380)));
fprintf('Rizado a la salida : %d codigos\n', max(y(100:380))-min(y(100:380)));