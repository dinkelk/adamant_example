from targets.pico import Pico_Base
import os.path


class Pico_Test(Pico_Base):
    """Test target for Pico that attempts to link AUnit."""
    def description(self):
        return ("Same as Pico_Development except it links with AUnit for unit tests.")

    def path_files(self):
        return list(set(super(Pico_Test, self).path_files() + ["Pico"]))

    def gpr_project_file(self):
        return os.path.join(
            os.environ["EXAMPLE_DIR"],
            "redo" + os.sep + "targets" + os.sep + "gpr" + os.sep + "pico_test.gpr",
        )
