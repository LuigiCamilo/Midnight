Space
Satellite Primos() -> planet {
    [planet]Quasar L = [];
    planet p = 2;
    orbit while(full) {
        moon esprimo = full;
        orbit q around L {
            if (p%q == 0) {
                esprimo = new;
                break;
            }
        }
        if (esprimo) {
            yield p;
            L.add(p);
        }
        p++;
    }
}

[planet]Satelline generador_primos = Primos();
print("esto no va a parar jaja salu2");
orbit p around generador_primos {
    print(p);
}
EndofSpace