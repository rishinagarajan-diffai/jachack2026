import from score { Trace }
import from viz { Export }

with entry {
    root spawn Trace(decay=0.45);
    root spawn Export(out="graph.html");
}
