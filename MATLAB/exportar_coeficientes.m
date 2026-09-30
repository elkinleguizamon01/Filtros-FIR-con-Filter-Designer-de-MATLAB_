% exportar_coeficientes.m
% Ejecutar DESPUÉS de tener Num en el workspace

INPUT_WIDTH  = 16;
COEFF_WIDTH  = 16;
OUTPUT_WIDTH = 16;
MAXIN = 1023;

S = 2^(INPUT_WIDTH + COEFF_WIDTH - OUTPUT_WIDTH - 1);  % 32768

h = Num(:).';
h = h / sum(h);
c = round(h * S);

m = ceil(numel(c)/2);
fprintf('Corrección central: %d\n', S - sum(c));
c(m) = c(m) + (S - sum(c));

fprintf('Coeficientes: %d\n', numel(c));
fprintf('Suma: %d (debe ser %d)\n', sum(c), S);
fprintf('Mín/Máx: %d / %d\n', min(c), max(c));
fprintf('Suma |c|: %d\n', sum(abs(c)));
fprintf('Margen acum: %.1f veces\n', ...
    2^(INPUT_WIDTH+COEFF_WIDTH-2)/(sum(abs(c))*MAXIN));

assert(sum(c) == S, 'Suma incorrecta');
assert(min(c) >= -2^(COEFF_WIDTH-1) && max(c) <= 2^(COEFF_WIDTH-1)-1, ...
    'Coeficiente no cabe en 16 bits');
assert(sum(abs(c))*MAXIN < 2^(INPUT_WIDTH+COEFF_WIDTH-2), ...
    'Acumulador puede desbordar');

fid = fopen('coeficientes.txt','w');
fprintf(fid,'type coefficients is array (0 to %d) of signed(%d downto 0);\n', ...
    numel(c)-1, COEFF_WIDTH-1);
fprintf(fid,'signal coeff_s : coefficients := (\n');
for k = 1:numel(c)
    v = mod(c(k), 2^COEFF_WIDTH);
    if mod(k-1,6) == 0, fprintf(fid,'    '); end
    if k < numel(c)
        fprintf(fid,'x"%04X", ', v);
    else
        fprintf(fid,'x"%04X");\n', v);
    end
    if mod(k,6) == 0 && k < numel(c), fprintf(fid,'\n'); end
end
fclose(fid);
disp('coeficientes.txt generado.');